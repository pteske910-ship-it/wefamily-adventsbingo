-- WeFamily Spielmanager: tighten RPC execution privileges
-- Review against the live schema before applying. This script changes privileges only;
-- it does not alter application data, table definitions, or row-level policies.

begin;

-- These helpers are called by RLS policies. Keep them executable for signed-in
-- users, but do not expose role checks to anonymous API clients.
revoke execute on function public.app_is_admin() from public, anon;
grant execute on function public.app_is_admin() to authenticated;

revoke execute on function public.app_is_owner() from public, anon;
grant execute on function public.app_is_owner() to authenticated;

-- Trigger-only functions must not be callable as public RPC endpoints.
revoke execute on function public.handle_new_auth_user() from public, anon, authenticated;
revoke execute on function public.handle_auth_user_email_update() from public, anon, authenticated;
revoke execute on function public.audit_app_user_role_change() from public, anon, authenticated;
revoke execute on function public.protect_owner_account() from public, anon, authenticated;
revoke execute on function public.set_updated_at() from public, anon, authenticated;
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;

-- These RPCs are used by authenticated app administrators only.
revoke execute on function public.import_legacy_bingo_event(text,text,jsonb) from public, anon;
grant execute on function public.import_legacy_bingo_event(text,text,jsonb) to authenticated;

revoke execute on function public.sync_legacy_bingo_event(uuid,timestamptz,jsonb) from public, anon;
grant execute on function public.sync_legacy_bingo_event(uuid,timestamptz,jsonb) to authenticated;

commit;
