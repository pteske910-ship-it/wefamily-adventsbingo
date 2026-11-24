-- WeFamily Adventsbingo: sichere Übernahme eines lokalen JSON-Backups
-- Einmal im Supabase SQL Editor ausführen, nachdem schema-v1.sql eingerichtet wurde.
-- Importiert eine Sicherung als eigene Veranstaltung. Original-JSON bleibt vollständig in legacy_data erhalten.
begin;

alter table public.events
  add column if not exists legacy_import_key text;

create unique index if not exists events_legacy_import_key_uidx
  on public.events (legacy_import_key)
  where legacy_import_key is not null;

create or replace function public.import_legacy_bingo_event(
  p_title text,
  p_import_key text,
  p_payload jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_event_id uuid;
  v_existing uuid;
  v_round jsonb;
  v_player jsonb;
  v_result jsonb;
  v_room record;
  v_round_id uuid;
  v_session text;
  v_round_no integer;
begin
  if not public.app_is_admin() then
    raise exception 'Not authorized';
  end if;
  if coalesce(trim(p_title), '') = '' then
    raise exception 'Event title is required';
  end if;
  if coalesce(trim(p_import_key), '') = '' then
    raise exception 'Import key is required';
  end if;
  if jsonb_typeof(p_payload) <> 'object'
     or jsonb_typeof(p_payload->'players') <> 'array'
     or jsonb_typeof(p_payload->'rounds') <> 'array'
     or jsonb_typeof(p_payload->'results') <> 'array' then
    raise exception 'Backup JSON is missing required arrays';
  end if;

  select id into v_existing
  from public.events
  where legacy_import_key = p_import_key;
  if v_existing is not null then
    return v_existing;
  end if;

  insert into public.events(title, event_type, status, created_by, legacy_import_key, legacy_data)
  values (
    trim(p_title), 'advent-bingo', 'draft', auth.uid(), p_import_key,
    jsonb_build_object('source', 'local-json-backup', 'original', p_payload)
  )
  returning id into v_event_id;

  for v_player in select value from jsonb_array_elements(p_payload->'players')
  loop
    if coalesce(v_player->>'id','') = '' then
      raise exception 'Participant without id in backup';
    end if;
    insert into public.event_participants(event_id, display_name, family, source_participant_id)
    values (v_event_id, coalesce(v_player->>'name','Unbenannt'), coalesce(v_player->>'family',''), (v_player->>'id')::uuid);
  end loop;

  for v_round in select value from jsonb_array_elements(p_payload->'rounds')
  loop
    insert into public.rounds(event_id, round_number, mode, points_per_bingo, note)
    values (
      v_event_id,
      (v_round->>'n')::integer,
      coalesce(v_round->>'mode','Normal'),
      coalesce(nullif(v_round->>'pointsPerBingo','')::numeric,1),
      coalesce(v_round->>'note','')
    );
  end loop;

  for v_result in select value from jsonb_array_elements(p_payload->'results')
  loop
    select id into v_round_id
    from public.rounds
    where event_id = v_event_id
      and round_number = (v_result->>'round')::integer;

    insert into public.bingo_results(
      event_id, round_id, participant_id, session_key, count, bingo_no, place, points
    )
    select
      v_event_id, v_round_id, p.id,
      coalesce(v_result->>'session','Spieltag'),
      greatest(1, coalesce(nullif(v_result->>'count','')::integer,1)),
      nullif(v_result->>'bingoNo','')::integer,
      nullif(v_result->>'place','')::integer,
      nullif(v_result->>'points','')::numeric
    from public.event_participants p
    where p.event_id = v_event_id
      and p.source_participant_id = (v_result->>'playerId')::uuid;

    if not found then
      raise exception 'Result refers to an unknown participant or round';
    end if;
  end loop;

  if jsonb_typeof(p_payload->'roomStats') = 'object' then
    for v_room in
      select key, value from jsonb_each(p_payload->'roomStats')
    loop
      v_session := split_part(v_room.key, '|', 1);
      v_round_no := split_part(v_room.key, '|', 2)::integer;
      select id into v_round_id from public.rounds
      where event_id = v_event_id and round_number = v_round_no;
      if v_round_id is not null then
        insert into public.room_statistics(
          event_id, session_key, round_id, start_count, current_count,
          peak_count, low_count, changes
        ) values (
          v_event_id, v_session, v_round_id,
          nullif(v_room.value->>'start','')::integer,
          nullif(v_room.value->>'current','')::integer,
          nullif(v_room.value->>'peak','')::integer,
          nullif(v_room.value->>'low','')::integer,
          coalesce(v_room.value->'changes','[]'::jsonb)
        );
      end if;
    end loop;
  end if;

  insert into public.audit_log(actor_user_id, action, target_type, target_id, details)
  values (auth.uid(), 'legacy_event_imported', 'event', v_event_id::text,
    jsonb_build_object('participants', jsonb_array_length(p_payload->'players'),
      'rounds', jsonb_array_length(p_payload->'rounds'),
      'results', jsonb_array_length(p_payload->'results')));

  return v_event_id;
end;
$$;

grant execute on function public.import_legacy_bingo_event(text,text,jsonb) to authenticated;

commit;
