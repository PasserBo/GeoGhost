-- =============================================================================
-- Remote update gate and operator switches
-- (docs/spec/changes/add-update-gate-and-switches/design.md)
--
--   * public.app_config: one row, readable by everyone, written only through
--     admin_set_app_config (service role, logged as action 'config').
--   * Every client request carries `X-GeoGhost-Version: <major.minor.patch>`.
--     Writes from clients below min_online_version are refused with hint
--     `update_required`; a missing header counts as too old.
--   * create_post: publishing_enabled = false → hint `publishing_paused`.
--   * upsert_profile, first profile only: signups_enabled = false → hint `signups_paused`.
--   * Reads (explore, posts) and account deletion are never gated.
--
-- create_post / upsert_profile / report_post keep their bodies: they move to the
-- private schema unchanged (their plpgsql labels are the function name, so the
-- name stays) and a public wrapper with the same signature runs the checks first,
-- so a paused or outdated client never sees a quota refusal instead.
-- =============================================================================

create table public.app_config (
  id                 boolean primary key default true check (id),
  min_online_version text not null default '1.1.0' check (min_online_version ~ '^\d{1,4}\.\d{1,4}\.\d{1,4}$'),
  latest_version     text not null default '1.1.0' check (latest_version ~ '^\d{1,4}\.\d{1,4}\.\d{1,4}$'),
  publishing_enabled boolean not null default true,
  signups_enabled    boolean not null default true,
  notice             jsonb,
  updated_at         timestamptz not null default now()
);
insert into public.app_config default values;

alter table public.app_config enable row level security;
create policy app_config_read on public.app_config for select to anon, authenticated using (true);
revoke all on table public.app_config from public, anon, authenticated;
grant select on table public.app_config to anon, authenticated;

alter table private.moderation_log drop constraint moderation_log_action_check;
alter table private.moderation_log add constraint moderation_log_action_check
  check (action in ('approve', 'reject', 'remove', 'ban', 'unban', 'config'));

-- -----------------------------------------------------------------------------
-- Version comparison: numeric major.minor.patch; missing or non-numeric parts are 0.
-- Same rule as the app's AppVersion (Swift).
-- -----------------------------------------------------------------------------
create function private.version_parts(v text)
returns integer[]
language sql immutable set search_path = ''
as $$
  select array[
    coalesce(nullif(substring(p[1] from '^\d{1,9}'), ''), '0')::integer,
    coalesce(nullif(substring(p[2] from '^\d{1,9}'), ''), '0')::integer,
    coalesce(nullif(substring(p[3] from '^\d{1,9}'), ''), '0')::integer]
  from (select string_to_array(btrim(coalesce(v, '')), '.') as p) s
$$;

create function private.version_lt(a text, b text)
returns boolean
language sql immutable set search_path = ''
as $$ select private.version_parts(a) < private.version_parts(b) $$;

-- The version the current request says it is; null outside a client request
-- or when the header is missing.
create function private.client_version()
returns text
language sql stable set search_path = ''
as $$
  select nullif(nullif(current_setting('request.headers', true), '')::json ->> 'x-geoghost-version', '')
$$;

-- Raises `update_required` when the request's app version is below min_online_version.
create function private.require_online_version()
returns void
language plpgsql stable security definer set search_path = ''
as $$
declare
  v   text := private.client_version();
  min text;
begin
  select c.min_online_version into min from public.app_config c;
  if v is null or private.version_lt(v, coalesce(min, '0.0.0')) then
    raise exception 'this app version is no longer supported for online features'
      using hint = 'update_required';
  end if;
end;
$$;

create function private.version_gate_trigger()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  perform private.require_online_version();
  return new;
end;
$$;

-- Trigger names start with "aa_" so they run before the existing before-insert
-- triggers (limits), which fire in name order.
create trigger aa_version_gate before insert on public.likes
  for each row execute function private.version_gate_trigger();
create trigger aa_version_gate before insert on public.saves
  for each row execute function private.version_gate_trigger();
create trigger aa_version_gate before insert on public.blocks
  for each row execute function private.version_gate_trigger();

-- -----------------------------------------------------------------------------
-- Wrappers
-- -----------------------------------------------------------------------------
alter function public.create_post(uuid, text, double precision, double precision, text, text, date, integer, integer)
  set schema private;
alter function public.upsert_profile(text, integer) set schema private;
alter function public.report_post(uuid, text, text) set schema private;
revoke all on function private.create_post(uuid, text, double precision, double precision, text, text, date, integer, integer)
  from public, anon, authenticated;
revoke all on function private.upsert_profile(text, integer) from public, anon, authenticated;
revoke all on function private.report_post(uuid, text, text) from public, anon, authenticated;

create function public.create_post(
  client_artwork_id uuid,
  kind              text,
  lat               double precision,
  lng               double precision,
  locality          text    default null,
  country_code      text    default null,
  captured_on       date    default null,
  width             integer default null,
  height            integer default null
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
begin
  perform private.require_online_version();
  if not (select c.publishing_enabled from public.app_config c) then
    raise exception 'publishing is paused' using hint = 'publishing_paused';
  end if;
  return private.create_post(
    client_artwork_id => create_post.client_artwork_id, kind => create_post.kind,
    lat => create_post.lat, lng => create_post.lng, locality => create_post.locality,
    country_code => create_post.country_code, captured_on => create_post.captured_on,
    width => create_post.width, height => create_post.height);
end;
$$;

create function public.upsert_profile(nickname text, terms_version integer)
returns public.profiles
language plpgsql security definer set search_path = ''
as $$
begin
  perform private.require_online_version();
  if auth.uid() is not null
     and not exists (select 1 from private.profiles pr where pr.id = auth.uid())
     and not (select c.signups_enabled from public.app_config c) then
    raise exception 'new members are paused' using hint = 'signups_paused';
  end if;
  return private.upsert_profile(nickname => upsert_profile.nickname,
                                terms_version => upsert_profile.terms_version);
end;
$$;

create function public.report_post(post_id uuid, reason text, note text default null)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
begin
  perform private.require_online_version();
  return private.report_post(post_id => report_post.post_id, reason => report_post.reason,
                             note => report_post.note);
end;
$$;

-- -----------------------------------------------------------------------------
-- Operator settings (service role only; the admin Worker passes the operator's email)
-- -----------------------------------------------------------------------------
create function public.admin_set_app_config(
  min_online_version text,
  latest_version     text,
  publishing_enabled boolean,
  signups_enabled    boolean,
  notice             jsonb,
  actor              text
)
returns public.app_config
language plpgsql security definer set search_path = ''
as $$
declare
  v_notice jsonb := admin_set_app_config.notice;
  k        text;
  val      jsonb;
  result   public.app_config;
begin
  if admin_set_app_config.min_online_version !~ '^\d{1,4}\.\d{1,4}\.\d{1,4}$'
     or admin_set_app_config.latest_version !~ '^\d{1,4}\.\d{1,4}\.\d{1,4}$' then
    raise exception 'versions must look like 1.2.3' using errcode = '22023', hint = 'invalid_argument';
  end if;
  if private.version_lt(admin_set_app_config.latest_version, admin_set_app_config.min_online_version) then
    raise exception 'latest_version must not be below min_online_version'
      using errcode = '22023', hint = 'invalid_argument';
  end if;
  if v_notice is not null and jsonb_typeof(v_notice) = 'null' then
    v_notice := null;
  end if;
  if v_notice is not null then
    if jsonb_typeof(v_notice) <> 'object' then
      raise exception 'notice must be an object' using errcode = '22023', hint = 'invalid_argument';
    end if;
    -- Drop blank languages; refuse unknown languages and over-long text.
    for k, val in select * from jsonb_each(v_notice) loop
      if k not in ('en', 'ja', 'zh-Hans') or jsonb_typeof(val) <> 'string'
         or char_length(val #>> '{}') > 280 then
        raise exception 'notice: unknown language or text too long' using errcode = '22023', hint = 'invalid_argument';
      end if;
      if btrim(val #>> '{}') = '' then
        v_notice := v_notice - k;
      end if;
    end loop;
    if v_notice = '{}'::jsonb then
      v_notice := null;
    end if;
  end if;

  update public.app_config c
     set min_online_version = admin_set_app_config.min_online_version,
         latest_version     = admin_set_app_config.latest_version,
         publishing_enabled = admin_set_app_config.publishing_enabled,
         signups_enabled    = admin_set_app_config.signups_enabled,
         notice             = v_notice,
         updated_at         = now()
   where c.id
  returning * into result;

  insert into private.moderation_log (actor, action, note)
  values (admin_set_app_config.actor, 'config',
          left(format('min %s, latest %s, publishing %s, signups %s, notice %s',
                      result.min_online_version, result.latest_version,
                      case when result.publishing_enabled then 'on' else 'paused' end,
                      case when result.signups_enabled then 'on' else 'paused' end,
                      case when result.notice is null then 'none'
                           else (select string_agg(x, '/' order by x) from jsonb_object_keys(result.notice) x) end),
               500));
  return result;
end;
$$;

-- -----------------------------------------------------------------------------
-- Grants
-- -----------------------------------------------------------------------------
revoke all on function private.version_parts(text), private.version_lt(text, text), private.client_version(),
                       private.require_online_version(), private.version_gate_trigger()
  from public, anon, authenticated;

revoke all on function public.create_post(uuid, text, double precision, double precision, text, text, date, integer, integer)
  from public, anon, authenticated;
revoke all on function public.upsert_profile(text, integer) from public, anon, authenticated;
revoke all on function public.report_post(uuid, text, text) from public, anon, authenticated;
revoke all on function public.admin_set_app_config(text, text, boolean, boolean, jsonb, text)
  from public, anon, authenticated;
grant execute on function public.create_post(uuid, text, double precision, double precision, text, text, date, integer, integer)
  to authenticated;
grant execute on function public.upsert_profile(text, integer) to authenticated;
grant execute on function public.report_post(uuid, text, text) to authenticated;
grant execute on function public.admin_set_app_config(text, text, boolean, boolean, jsonb, text) to service_role;
