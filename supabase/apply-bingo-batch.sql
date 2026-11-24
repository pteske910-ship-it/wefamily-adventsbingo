-- WeFamily Adventsbingo: atomare Mehrfachänderungen
-- Alle Operationen eines Speichervorgangs werden in EINER Datenbanktransaktion ausgeführt.
-- Bei einem Fehler wird der gesamte Aufruf zurückgerollt.
begin;

create or replace function public.apply_bingo_changes(
  p_event_id uuid,
  p_expected_updated_at timestamptz,
  p_changes jsonb
)
returns timestamptz
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_expected timestamptz := p_expected_updated_at;
  v_change jsonb;
  v_count integer := 0;
begin
  if not public.app_is_admin() then
    raise exception 'Not authorized';
  end if;
  if p_event_id is null or p_expected_updated_at is null
     or jsonb_typeof(p_changes) <> 'array' then
    raise exception 'Event id, expected version and changes array are required';
  end if;
  if jsonb_array_length(p_changes) > 250 then
    raise exception 'Too many changes in one batch (maximum 250)';
  end if;

  -- Lock the event for the duration of the whole RPC.
  perform 1 from public.events e
  where e.id = p_event_id and e.updated_at = p_expected_updated_at
  for update;
  if not found then
    raise exception 'VERSION_CONFLICT: Cloud data changed on another device. Reload before saving.';
  end if;

  for v_change in select value from jsonb_array_elements(p_changes)
  loop
    if jsonb_typeof(v_change) <> 'object'
       or jsonb_typeof(v_change->'payload') <> 'object'
       or coalesce(v_change->>'entity','') = ''
       or coalesce(v_change->>'operation','') = '' then
      raise exception 'Each change must contain entity, operation and object payload';
    end if;

    v_expected := public.apply_bingo_change(
      p_event_id,
      v_expected,
      v_change->>'entity',
      v_change->>'operation',
      v_change->'payload'
    );
    v_count := v_count + 1;
  end loop;

  if v_count = 0 then
    return p_expected_updated_at;
  end if;
  return v_expected;
end;
$$;

revoke all on function public.apply_bingo_changes(uuid,timestamptz,jsonb) from public, anon;
grant execute on function public.apply_bingo_changes(uuid,timestamptz,jsonb) to authenticated;

commit;
