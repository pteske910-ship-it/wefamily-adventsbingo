-- Stable source IDs for individual Bingo result synchronization.
-- Safe to run on the existing imported event: existing result IDs are copied as source IDs.
begin;

alter table public.bingo_results
  add column if not exists source_result_id uuid;

update public.bingo_results
set source_result_id = id
where source_result_id is null;

create unique index if not exists bingo_results_event_source_result_uidx
  on public.bingo_results(event_id, source_result_id)
  where source_result_id is not null;

commit;
