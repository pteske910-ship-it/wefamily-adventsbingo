-- WeFamily Adventsbingo: atomarer Snapshot-Sync mit Versionsprüfung
-- Auf dem Entwicklungszweig. Noch nicht in der Live-App aktivieren.
-- Ersetzt innerhalb einer Transaktion den vollständigen Datenstand EINER Veranstaltung.
begin;

create or replace function public.sync_legacy_bingo_event(
  p_event_id uuid,
  p_expected_updated_at timestamptz,
  p_payload jsonb
)
returns timestamptz
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_current_updated_at timestamptz;
  v_new_updated_at timestamptz;
  v_player jsonb;
  v_round jsonb;
  v_result jsonb;
  v_room record;
  v_round_id uuid;
  v_session text;
  v_round_no integer;
begin
  if not public.app_is_admin() then
    raise exception 'Not authorized';
  end if;

  if p_event_id is null or p_expected_updated_at is null then
    raise exception 'Event id and expected version are required';
  end if;

  if jsonb_typeof(p_payload) <> 'object'
     or coalesce(jsonb_typeof(p_payload->'players'), '') <> 'array'
     or coalesce(jsonb_typeof(p_payload->'rounds'), '') <> 'array'
     or coalesce(jsonb_typeof(p_payload->'results'), '') <> 'array'
     or (p_payload ? 'roomStats' and jsonb_typeof(p_payload->'roomStats') <> 'object') then
    raise exception 'Payload has an invalid structure';
  end if;

  select e.updated_at into v_current_updated_at
  from public.events e
  where e.id = p_event_id
  for update;

  if not found then
    raise exception 'Event not found';
  end if;

  if v_current_updated_at is distinct from p_expected_updated_at then
    raise exception 'VERSION_CONFLICT: Cloud data changed on another device. Reload before saving.';
  end if;

  -- Alte abhängige Daten in FK-sicherer Reihenfolge entfernen.
  delete from public.bingo_results where event_id = p_event_id;
  delete from public.room_statistics where event_id = p_event_id;
  delete from public.event_participants where event_id = p_event_id;
  delete from public.rounds where event_id = p_event_id;

  for v_player in select value from jsonb_array_elements(p_payload->'players')
  loop
    if coalesce(v_player->>'id','') = '' then
      raise exception 'Participant without id';
    end if;
    insert into public.event_participants(
      event_id, display_name, family, source_participant_id
    ) values (
      p_event_id,
      coalesce(v_player->>'name','Unbenannt'),
      coalesce(v_player->>'family',''),
      (v_player->>'id')::uuid
    );
  end loop;

  for v_round in select value from jsonb_array_elements(p_payload->'rounds')
  loop
    insert into public.rounds(
      event_id, round_number, mode, points_per_bingo, note
    ) values (
      p_event_id,
      (v_round->>'n')::integer,
      coalesce(v_round->>'mode','Normal'),
      coalesce(nullif(v_round->>'pointsPerBingo','')::numeric,1),
      coalesce(v_round->>'note','')
    );
  end loop;

  for v_result in select value from jsonb_array_elements(p_payload->'results')
  loop
    select r.id into v_round_id
    from public.rounds r
    where r.event_id = p_event_id
      and r.round_number = (v_result->>'round')::integer;

    if v_round_id is null then
      raise exception 'Result refers to an unknown round';
    end if;

    insert into public.bingo_results(
      event_id, round_id, participant_id, session_key,
      count, bingo_no, place, points
    )
    select
      p_event_id, v_round_id, p.id,
      coalesce(v_result->>'session','Spieltag'),
      greatest(1, coalesce(nullif(v_result->>'count','')::integer,1)),
      nullif(v_result->>'bingoNo','')::integer,
      nullif(v_result->>'place','')::integer,
      nullif(v_result->>'points','')::numeric
    from public.event_participants p
    where p.event_id = p_event_id
      and p.source_participant_id = (v_result->>'playerId')::uuid;

    if not found then
      raise exception 'Result refers to an unknown participant';
    end if;
  end loop;

  if jsonb_typeof(p_payload->'roomStats') = 'object' then
    for v_room in
      select key, value from jsonb_each(p_payload->'roomStats')
    loop
      v_session := split_part(v_room.key, '|', 1);
      v_round_no := split_part(v_room.key, '|', 2)::integer;

      select r.id into v_round_id
      from public.rounds r
      where r.event_id = p_event_id and r.round_number = v_round_no;

      if v_round_id is null then
        raise exception 'Room statistic refers to an unknown round';
      end if;

      insert into public.room_statistics(
        event_id, session_key, round_id, start_count, current_count,
        peak_count, low_count, changes
      ) values (
        p_event_id, v_session, v_round_id,
        nullif(v_room.value->>'start','')::integer,
        nullif(v_room.value->>'current','')::integer,
        nullif(v_room.value->>'peak','')::integer,
        nullif(v_room.value->>'low','')::integer,
        coalesce(v_room.value->'changes','[]'::jsonb)
      );
    end loop;
  end if;

  update public.events
  set
    legacy_data = jsonb_set(
      coalesce(legacy_data, '{}'::jsonb),
      '{original}', p_payload, true
    ),
    settings = jsonb_set(
      coalesce(settings, '{}'::jsonb),
      '{scoring}', coalesce(p_payload->'scoring', '{}'::jsonb), true
    )
  where id = p_event_id
  returning updated_at into v_new_updated_at;

  return v_new_updated_at;
end;
$$;

grant execute on function public.sync_legacy_bingo_event(uuid,timestamptz,jsonb)
  to authenticated;

commit;
