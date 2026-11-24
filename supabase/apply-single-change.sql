-- WeFamily Adventsbingo: einzelne, versionsgesicherte Änderungen
-- Kein Vollimport: jede RPC ändert genau einen Datensatz und prüft die Event-Version.
begin;

create unique index if not exists event_participants_event_source_uidx
  on public.event_participants(event_id, source_participant_id)
  where source_participant_id is not null;

create or replace function public.apply_bingo_change(
  p_event_id uuid,
  p_expected_updated_at timestamptz,
  p_entity text,
  p_operation text,
  p_payload jsonb
)
returns timestamptz
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_current timestamptz;
  v_new timestamptz;
  v_round_id uuid;
  v_participant_id uuid;
  v_source_id uuid;
  v_session text;
  v_round_no integer;
begin
  if not public.app_is_admin() then
    raise exception 'Not authorized';
  end if;
  if p_event_id is null or p_expected_updated_at is null
     or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Event id, expected version and object payload are required';
  end if;
  if p_operation not in ('upsert','delete') then
    raise exception 'Unsupported operation';
  end if;
  select e.updated_at into v_current
  from public.events e where e.id = p_event_id for update;
  if not found then raise exception 'Event not found'; end if;
  if v_current is distinct from p_expected_updated_at then
    raise exception 'VERSION_CONFLICT: Cloud data changed on another device. Reload before saving.';
  end if;

  if p_entity = 'participant' then
    v_source_id := nullif(p_payload->>'id','')::uuid;
    if v_source_id is null then raise exception 'Participant source id is required'; end if;
    if p_operation = 'upsert' then
      insert into public.event_participants(event_id,display_name,family,source_participant_id)
      values (p_event_id,coalesce(nullif(p_payload->>'name',''),'Unbenannt'),coalesce(p_payload->>'family',''),v_source_id)
      on conflict (event_id,source_participant_id) where source_participant_id is not null
      do update set display_name=excluded.display_name,family=excluded.family;
    else
      if exists (
        select 1 from public.bingo_results b
        join public.event_participants p on p.id=b.participant_id and p.event_id=b.event_id
        where b.event_id=p_event_id and p.source_participant_id=v_source_id
      ) then raise exception 'Participant has Bingo results; removal is blocked to preserve history'; end if;
      delete from public.event_participants
      where event_id=p_event_id and source_participant_id=v_source_id;
    end if;

  elsif p_entity = 'round' then
    v_round_no := (p_payload->>'n')::integer;
    if v_round_no is null or v_round_no not between 1 and 250 then raise exception 'Round number must be between 1 and 250'; end if;
    if p_operation = 'upsert' then
      insert into public.rounds(event_id,round_number,mode,points_per_bingo,note)
      values (p_event_id,v_round_no,coalesce(p_payload->>'mode','Normal'),coalesce(nullif(p_payload->>'pointsPerBingo','')::numeric,1),coalesce(p_payload->>'note',''))
      on conflict (event_id,round_number)
      do update set mode=excluded.mode,points_per_bingo=excluded.points_per_bingo,note=excluded.note;
    else
      if exists(select 1 from public.bingo_results where event_id=p_event_id and round_id in (select id from public.rounds where event_id=p_event_id and round_number=v_round_no))
         or exists(select 1 from public.room_statistics where event_id=p_event_id and round_id in (select id from public.rounds where event_id=p_event_id and round_number=v_round_no)) then
        raise exception 'Round contains saved data; removal is blocked';
      end if;
      delete from public.rounds where event_id=p_event_id and round_number=v_round_no;
    end if;

  elsif p_entity = 'result' then
    v_source_id := nullif(p_payload->>'id','')::uuid;
    if v_source_id is null then raise exception 'Result source id is required'; end if;
    if p_operation = 'upsert' then
      v_round_no := (p_payload->>'round')::integer;
      select id into v_round_id from public.rounds where event_id=p_event_id and round_number=v_round_no;
      select id into v_participant_id from public.event_participants where event_id=p_event_id and source_participant_id=(p_payload->>'playerId')::uuid;
      if v_round_id is null or v_participant_id is null then raise exception 'Result references an unknown round or participant'; end if;
      insert into public.bingo_results(event_id,round_id,participant_id,session_key,count,bingo_no,place,points,room_count,source_result_id)
      values (p_event_id,v_round_id,v_participant_id,coalesce(nullif(p_payload->>'session',''),'Spieltag'),greatest(1,coalesce(nullif(p_payload->>'count','')::integer,1)),nullif(p_payload->>'bingoNo','')::integer,nullif(p_payload->>'place','')::integer,nullif(p_payload->>'points','')::numeric,nullif(p_payload->>'roomCount','')::integer,v_source_id)
      on conflict (event_id,source_result_id) where source_result_id is not null
      do update set round_id=excluded.round_id,participant_id=excluded.participant_id,session_key=excluded.session_key,count=excluded.count,bingo_no=excluded.bingo_no,place=excluded.place,points=excluded.points,room_count=excluded.room_count;
    else
      delete from public.bingo_results where event_id=p_event_id and source_result_id=v_source_id;
    end if;

  elsif p_entity = 'meta' then
    -- Only event metadata owned by this app is patched; unrelated legacy_data is preserved.
    update public.events
    set legacy_data = jsonb_set(
          jsonb_set(coalesce(legacy_data,'{}'::jsonb),'{original,presence}',coalesce(p_payload->'presence','{}'::jsonb),true),
          '{original,attendance}',coalesce(p_payload->'attendance','{}'::jsonb),true
        ),
        settings = jsonb_set(coalesce(settings,'{}'::jsonb),'{scoring}',coalesce(p_payload->'scoring','{}'::jsonb),true)
    where id = p_event_id;

  elsif p_entity = 'room' then
    v_session := coalesce(nullif(p_payload->>'session',''),'Spieltag');
    v_round_no := (p_payload->>'round')::integer;
    select id into v_round_id from public.rounds where event_id=p_event_id and round_number=v_round_no;
    if v_round_id is null then raise exception 'Room statistic references an unknown round'; end if;
    if p_operation = 'upsert' then
      insert into public.room_statistics(event_id,session_key,round_id,start_count,current_count,peak_count,low_count,changes)
      values (p_event_id,v_session,v_round_id,nullif(p_payload->>'start','')::integer,nullif(p_payload->>'current','')::integer,nullif(p_payload->>'peak','')::integer,nullif(p_payload->>'low','')::integer,coalesce(p_payload->'changes','[]'::jsonb))
      on conflict (event_id,session_key,round_id)
      do update set start_count=excluded.start_count,current_count=excluded.current_count,peak_count=excluded.peak_count,low_count=excluded.low_count,changes=excluded.changes;
    else
      delete from public.room_statistics where event_id=p_event_id and session_key=v_session and round_id=v_round_id;
    end if;
  else
    raise exception 'Unsupported entity';
  end if;

  update public.events set updated_at=now() where id=p_event_id returning updated_at into v_new;
  return v_new;
end;
$$;

revoke all on function public.apply_bingo_change(uuid,timestamptz,text,text,jsonb) from public, anon;
grant execute on function public.apply_bingo_change(uuid,timestamptz,text,text,jsonb) to authenticated;

commit;
