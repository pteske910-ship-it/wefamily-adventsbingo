create table if not exists public.members (
  id uuid primary key default gen_random_uuid(),
  display_name text not null,
  family text not null default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint members_display_name_not_blank check (length(btrim(display_name)) > 0)
);

create unique index if not exists members_name_family_ci_uidx
  on public.members (lower(btrim(display_name)), lower(btrim(family)));

alter table public.members enable row level security;

drop policy if exists "Administrators manage members" on public.members;
create policy "Administrators manage members"
  on public.members for all to authenticated
  using (public.app_is_admin())
  with check (public.app_is_admin());

grant select, insert, update, delete on public.members to authenticated;

alter table public.event_participants
  add column if not exists member_id uuid references public.members(id) on delete set null;

insert into public.members (display_name, family)
select distinct on (lower(btrim(ep.display_name)), lower(btrim(coalesce(ep.family,''))))
  btrim(ep.display_name), btrim(coalesce(ep.family,''))
from public.event_participants ep
where nullif(btrim(ep.display_name),'') is not null
order by lower(btrim(ep.display_name)), lower(btrim(coalesce(ep.family,''))), ep.created_at asc
on conflict do nothing;

update public.event_participants ep
set member_id = m.id
from public.members m
where ep.member_id is null
  and lower(btrim(ep.display_name)) = lower(btrim(m.display_name))
  and lower(btrim(coalesce(ep.family,''))) = lower(btrim(m.family));

create index if not exists event_participants_member_id_idx
  on public.event_participants(member_id);
