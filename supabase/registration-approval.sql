-- WeFamily registration + owner approval workflow
-- Apply AFTER schema-v1.sql on the existing Supabase project.
-- Existing app_users rows become active; newly registered users start pending.
begin;

alter table public.app_users
  add column if not exists email text,
  add column if not exists account_status text not null default 'active'
    check (account_status in ('pending','active','rejected'));

create index if not exists app_users_account_status_created_idx
  on public.app_users(account_status, created_at);

-- Existing app roles only grant access after explicit activation.
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
      and u.account_status = 'active'
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
      and u.account_status = 'active'
      and u.app_role = 'owner'
  );
$$;

-- New Auth accounts are always administrators pending Pascal's approval.
-- No role or status is accepted from user-supplied metadata.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.app_users(user_id, display_name, email, app_role, account_status)
  values (
    new.id,
    left(coalesce(new.raw_user_meta_data ->> 'display_name', ''), 80),
    lower(new.email),
    'administrator',
    'pending'
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_app_profile on auth.users;
create trigger on_auth_user_created_app_profile
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- Keep the stored email current if the user changes it through Auth.
create or replace function public.handle_auth_user_email_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.email is distinct from old.email then
    update public.app_users set email = lower(new.email)
    where user_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_email_updated_app_profile on auth.users;
create trigger on_auth_user_email_updated_app_profile
  after update of email on auth.users
  for each row execute function public.handle_auth_user_email_update();

-- The owner may approve/reject accounts. A user may only read their own profile.
-- Recreate the owner update policy so it remains explicitly owner-only.
drop policy if exists app_users_owner_update on public.app_users;
create policy app_users_owner_update on public.app_users
for update to authenticated
using (public.app_is_owner())
with check (public.app_is_owner());

-- Do not permit client-side self-enrolment into app_users.
revoke insert on public.app_users from anon, authenticated;
grant select, update, delete on public.app_users to authenticated;

-- Protect owner identity and prevent a second owner from being created here.
create or replace function public.protect_owner_account()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and old.app_role = 'owner' then
    raise exception 'The owner account cannot be deleted';
  end if;
  if tg_op = 'UPDATE' and old.app_role = 'owner'
     and (new.app_role <> 'owner' or new.account_status <> 'active') then
    raise exception 'The owner role and active status cannot be revoked';
  end if;
  if tg_op = 'UPDATE' and old.app_role <> 'owner' and new.app_role = 'owner' then
    raise exception 'A second owner cannot be created through this operation';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$;

-- Expand the existing owner-protection trigger to cover status-only changes too.
drop trigger if exists app_users_protect_owner on public.app_users;
create trigger app_users_protect_owner
before update or delete on public.app_users
for each row execute function public.protect_owner_account();

commit;
