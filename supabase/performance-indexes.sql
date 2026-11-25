-- WeFamily Spielmanager: indexes for existing foreign-key access paths
-- Safe additive migration: creates indexes only; no data is changed.
begin;

create index if not exists audit_log_actor_user_id_idx
  on public.audit_log(actor_user_id);
create index if not exists bingo_results_event_participant_idx
  on public.bingo_results(event_id, participant_id);
create index if not exists bingo_results_event_round_idx
  on public.bingo_results(event_id, round_id);
create index if not exists events_created_by_idx
  on public.events(created_by);
create index if not exists room_statistics_event_round_idx
  on public.room_statistics(event_id, round_id);

commit;
