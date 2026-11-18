-- =============================================================================
-- LOCAL TESTS ONLY — never run this on a Supabase project.
--
-- Minimal stand-in for what Supabase provides, so the migration and the tests
-- can run on a plain postgres:16 container:
--   * roles anon / authenticated / service_role (service_role bypasses RLS)
--   * schema auth with auth.users and auth.uid() (reads request.jwt.claims.sub,
--     like PostgREST sets it per request)
--   * Supabase's default privileges on schema public (ALL to the API roles),
--     so the migration's explicit revokes are actually exercised
--   * a tiny `tests` schema with assertion helpers
-- =============================================================================

create role anon nologin noinherit;
create role authenticated nologin noinherit;
create role service_role nologin noinherit bypassrls;

create schema auth;
grant usage on schema auth to anon, authenticated, service_role;

create table auth.users (
  id           uuid primary key,
  is_anonymous boolean not null default true
);

create function auth.uid() returns uuid
language sql stable
as $$
  select nullif(nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub', '')::uuid
$$;
grant execute on function auth.uid() to anon, authenticated, service_role;

grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables    to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Test helpers
-- -----------------------------------------------------------------------------
create schema tests;
grant usage on schema tests to public;

create function tests.ok(cond boolean, description text) returns void
language plpgsql as $$
begin
  if cond is distinct from true then
    raise exception 'not ok - %', description;
  end if;
  raise notice 'ok - %', description;
end $$;

create function tests.eq(got anyelement, expected anyelement, description text) returns void
language plpgsql as $$
begin
  if got is distinct from expected then
    raise exception 'not ok - % (got %, expected %)', description, got, expected;
  end if;
  raise notice 'ok - %', description;
end $$;

-- Runs `query`; passes if it raises an error whose HINT equals expected_hint.
create function tests.throws_hint(query text, expected_hint text, description text) returns void
language plpgsql as $$
declare
  h text; m text; s text;
begin
  begin
    execute query;
  exception when others then
    get stacked diagnostics h = pg_exception_hint, m = message_text, s = returned_sqlstate;
    if h is not distinct from expected_hint then
      raise notice 'ok - %', description;
      return;
    end if;
    raise exception 'not ok - % (expected hint %, got hint % / % %)', description, expected_hint, h, s, m;
  end;
  raise exception 'not ok - % (no error raised)', description;
end $$;

-- Runs `query`; passes if it raises an error with SQLSTATE expected_state.
create function tests.throws_state(query text, expected_state text, description text) returns void
language plpgsql as $$
declare
  m text; s text;
begin
  begin
    execute query;
  exception when others then
    get stacked diagnostics m = message_text, s = returned_sqlstate;
    if s = expected_state then
      raise notice 'ok - %', description;
      return;
    end if;
    raise exception 'not ok - % (expected sqlstate %, got % %)', description, expected_state, s, m;
  end;
  raise exception 'not ok - % (no error raised)', description;
end $$;

-- Impersonate a PostgREST request. Call `set role ...` separately (top level).
create function tests.claims(uid uuid) returns void
language sql as $$
  select set_config('request.jwt.claims',
    case when uid is null then '{"role":"anon"}'
         else json_build_object('sub', uid, 'role', 'authenticated')::text end, false);
$$;

-- Every app request carries X-GeoGhost-Version (add-update-gate-and-switches). Tests run as a
-- current app unless they say otherwise with tests.version(); new sessions pick this up.
alter database postgres set "request.headers" to '{"x-geoghost-version":"1.1.0"}';

-- Pretend the request came from this app version (null = no header).
create function tests.version(v text) returns void
language sql as $$
  select set_config('request.headers',
    case when v is null then '{}' else json_build_object('x-geoghost-version', v)::text end, false);
$$;
