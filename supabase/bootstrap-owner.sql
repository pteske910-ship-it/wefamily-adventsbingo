-- Run only AFTER schema-v1.sql has completed successfully.
-- This creates the first owner profile for the already-created Auth user.
insert into public.app_users (user_id, display_name, app_role)
values (
  'ed55e873-9091-469c-9bb8-df1ce18382e5'::uuid,
  '',
  'owner'
);
