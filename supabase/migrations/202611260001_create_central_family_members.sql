create table if not exists public.members (
  id uuid primary key default gen_random_uuid(),
  display_name text not null check (length(btrim(display_name)) between 1 and 80),
  family text not null default '' check (length(family) <= 80),
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists members_name_family_unique
  on public.members (lower(btrim(display_name)), lower(btrim(family)));

create index if not exists members_active_name_idx
  on public.members (is_active, lower(display_name));

alter table public.members enable row level security;

revoke all on table public.members from anon, public;
grant select, insert, update, delete on table public.members to authenticated;

drop policy if exists "Administrators manage members" on public.members;
drop policy if exists members_admin_all on public.members;
create policy members_admin_all
  on public.members
  for all
  to authenticated
  using ((select public.app_is_admin()))
  with check ((select public.app_is_admin()));

drop trigger if exists members_set_updated_at on public.members;
create trigger members_set_updated_at
  before update on public.members
  for each row execute function public.set_updated_at();

alter table public.event_participants
  add column if not exists member_id uuid references public.members(id) on delete set null;

create index if not exists event_participants_member_id_idx
  on public.event_participants(member_id);