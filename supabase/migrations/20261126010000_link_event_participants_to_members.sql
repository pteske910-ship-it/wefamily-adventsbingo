-- Link event-specific participant rows to the central family roster.
-- display_name and family intentionally remain unchanged as historical snapshots.

alter table public.event_participants
  add column if not exists member_id uuid
  references public.members(id) on delete restrict;

create unique index if not exists event_participants_event_member_uidx
  on public.event_participants(event_id, member_id)
  where member_id is not null;

create index if not exists event_participants_member_id_idx
  on public.event_participants(member_id);

comment on column public.event_participants.member_id is
  'Optional link to the central member record. display_name and family remain the historical event-time snapshot.';
