-- WeFamily Spielmanager: initial Supabase schema
-- Apply only to a NEW project after reviewing. This script does not import user data.
-- Bootstrap the first owner separately after the first account has signed in.

begin;

create extension if not exists pgcrypto;

create table if not exists public.app_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  app_role text not null check (app_role in ('owner', 'administrator')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  event_type text not null default 'advent-bingo',
  status text not null default 'draft'
    check (status in ('draft', 'active', 'archived')),
  created_by uuid not null references auth.users(id),
  settings jsonb not null default
    '{"sessionLabels":["1. Advent","2. Advent","3. Advent","4. Advent"],"scoring":{"mode":"mode","normal":2,"power":1,"blackout":3,"placements":[10,8,7,6,5,4,3,2,1,1]}}'::jsonb,
  legacy_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id)
);

create table if not exists public.event_participants (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  display_name text not null,
  family text not null default '',
  source_participant_id uuid,
  created_at timestamptz not null default now(),
  unique (event_id, id)
);

create table if not exists public.rounds (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  round_number integer not null check (round_number between 1 and 250),
  mode text not null default 'Normal',
  points_per_bingo numeric not null default 1,
  note text not null default '',
  created_at timestamptz not null default now(),
  unique (event_id, id),
  unique (event_id, round_number)
);

create table if not exists public.bingo_results (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  round_id uuid not null,
  participant_id uuid not null,
  session_key text not null,
  count integer not null default 1 check (count > 0),
  bingo_no integer,
  place integer,
  points numeric,
  room_count integer check (room_count is null or room_count >= 0),
  created_at timestamptz not null default now(),
  foreign key (event_id, round_id)
    references public.rounds(event_id, id) on delete cascade,
  foreign key (event_id, participant_id)
    references public.event_participants(event_id, id) on delete cascade
);

create table if not exists public.room_statistics (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  session_key text not null,
  round_id uuid not null,
  start_count integer check (start_count is null or start_count >= 0),
  current_count integer check (current_count is null or current_count >= 0),
  peak_count integer check (peak_count is null or peak_count >= 0),
  low_count integer check (low_count is null or low_count >= 0),
  changes jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (event_id, round_id)
    references public.rounds(event_id, id) on delete cascade,
  unique (event_id, session_key, round_id)
);

create table if not exists public.audit_log (
  id bigint generated always as identity primary key,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  target_type text not null,
  target_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.app_is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.app_users u
    where u.user_id = (select auth.uid())
      and u.app_role in ('owner', 'administrator')
  );
$$;

create or replace function public.app_is_owner()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.app_users u
    where u.user_id = (select auth.uid())
      and u.app_role = 'owner'
  );
$$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists events_set_updated_at on public.events;
create trigger events_set_updated_at before update on public.events
for each row execute function public.set_updated_at();

drop trigger if exists app_users_set_updated_at on public.app_users;
create trigger app_users_set_updated_at before update on public.app_users
for each row execute function public.set_updated_at();

drop trigger if exists room_statistics_set_updated_at on public.room_statistics;
create trigger room_statistics_set_updated_at before update on public.room_statistics
for each row execute function public.set_updated_at();

alter table public.app_users enable row level security;
alter table public.events enable row level security;
alter table public.event_participants enable row level security;
alter table public.rounds enable row level security;
alter table public.bingo_results enable row level security;
alter table public.room_statistics enable row level security;
alter table public.audit_log enable row level security;

-- App role records are visible to the owner only. Role changes are owner-only.
drop policy if exists app_users_owner_select on public.app_users;
drop policy if exists app_users_self_select on public.app_users;
drop policy if exists app_users_select on public.app_users;
create policy app_users_select on public.app_users
for select to authenticated
using (public.app_is_owner() or user_id = (select auth.uid()));

drop policy if exists app_users_owner_update on public.app_users;
create policy app_users_owner_update on public.app_users
for update to authenticated using (public.app_is_owner()) with check (public.app_is_owner());

drop policy if exists app_users_owner_delete on public.app_users;
create policy app_users_owner_delete on public.app_users
for delete to authenticated using (public.app_is_owner());

-- Both the owner and administrators may manage all Bingo events and their data.
drop policy if exists events_admin_all on public.events;
create policy events_admin_all on public.events
for all to authenticated
using (public.app_is_admin())
with check (public.app_is_admin());

drop policy if exists participants_admin_all on public.event_participants;
create policy participants_admin_all on public.event_participants
for all to authenticated
using (public.app_is_admin())
with check (public.app_is_admin());

drop policy if exists rounds_admin_all on public.rounds;
create policy rounds_admin_all on public.rounds
for all to authenticated
using (public.app_is_admin())
with check (public.app_is_admin());

drop policy if exists results_admin_all on public.bingo_results;
create policy results_admin_all on public.bingo_results
for all to authenticated
using (public.app_is_admin())
with check (public.app_is_admin());

drop policy if exists room_statistics_admin_all on public.room_statistics;
create policy room_statistics_admin_all on public.room_statistics
for all to authenticated
using (public.app_is_admin())
with check (public.app_is_admin());

drop policy if exists audit_log_owner_select on public.audit_log;
create policy audit_log_owner_select on public.audit_log
for select to authenticated using (public.app_is_owner());

-- Record changes to application roles. This function writes only the role-change audit entry.
create or replace function public.audit_app_user_role_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.audit_log(actor_user_id, action, target_type, target_id, details)
  values (
    (select auth.uid()),
    case when tg_op = 'DELETE' then 'role_removed' else 'role_changed' end,
    'app_user',
    coalesce(old.user_id, new.user_id)::text,
    case
      when tg_op = 'DELETE' then jsonb_build_object('old_role', old.app_role)
      else jsonb_build_object('old_role', old.app_role, 'new_role', new.app_role)
    end
  );
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function public.protect_owner_account()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and old.app_role = 'owner' then
    raise exception 'The owner account cannot be deleted';
  end if;
  if tg_op = 'UPDATE' and old.app_role = 'owner' and new.app_role <> 'owner' then
    raise exception 'The owner role cannot be revoked or changed';
  end if;
  if tg_op = 'UPDATE' and old.app_role <> 'owner' and new.app_role = 'owner' then
    raise exception 'A second owner cannot be created through this operation';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists app_users_protect_owner on public.app_users;
create trigger app_users_protect_owner
before update of app_role or delete on public.app_users
for each row execute function public.protect_owner_account();

drop trigger if exists app_users_audit_role_change on public.app_users;
create trigger app_users_audit_role_change
after update of app_role or delete on public.app_users
for each row execute function public.audit_app_user_role_change();

-- No client-side insert/update/delete policy for audit_log.
revoke all on public.app_users, public.events, public.event_participants,
  public.rounds, public.bingo_results, public.room_statistics, public.audit_log
from anon;

grant select, insert, update, delete on public.events,
  public.event_participants, public.rounds, public.bingo_results,
  public.room_statistics to authenticated;
grant select, update, delete on public.app_users to authenticated;
grant select on public.audit_log to authenticated;
grant usage, select on sequence public.audit_log_id_seq to authenticated;

-- Cover foreign keys used for joins and parent-row updates/deletes.
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
