-- The service role (the API Worker's version check, the admin console's Settings page) reads
-- app_config directly. Supabase does not grant new tables to service_role on this project, so
-- without this the Worker answered 502 to every upload and retraction.
grant select on table public.app_config to service_role;
