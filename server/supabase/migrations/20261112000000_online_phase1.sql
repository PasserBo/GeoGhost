-- =============================================================================
-- GeoGhost online phase 1
-- Contract: docs/spec/changes/setup-online-backend/design.md (§4 data, §5 RLS/RPC, §6 quotas)
--
-- Conventions
--   * All day / month quota windows are computed in UTC
--     (day = [00:00 UTC today, 00:00 UTC tomorrow), month = calendar month in UTC).
--   * Every table has RLS enabled. Grants to anon / authenticated are revoked and
--     re-granted explicitly (Supabase grants ALL on new public objects by default).
--   * Security-definer functions use `set search_path = ''` and fully qualified names.
--   * Refusals raise P0001 with a fixed `hint` (§6); PostgREST passes it through.
--     Extra hints used here (not refusals, mostly client bugs):
--       not_authenticated, invalid_argument, not_found, invalid_status
--
-- Layout
--   public.profiles is a VIEW over private.profiles: everyone can read
--   id / nickname / avatar_post_id; every other column is NULL unless the row is
--   the caller's own (§5 "其余列只有本人可读" cannot be expressed with RLS alone,
--   which filters rows, not columns). The base table lives in schema `private`,
--   which PostgREST does not expose. Moderation (ban) is done on
--   private.profiles from the SQL editor.
-- =============================================================================

create schema if not exists private;
revoke all on schema private from public;
-- Needed so RLS policies evaluated as anon / authenticated can call
-- private.author_visible(); no table in this schema is granted to them.
grant usage on schema private to anon, authenticated;

-- -----------------------------------------------------------------------------
-- quota_config (§6)
-- -----------------------------------------------------------------------------
create table public.quota_config (
  key   text primary key,
  value integer not null check (value >= 0)
);

insert into public.quota_config (key, value) values
  ('posts_per_month',       20),
  ('posts_per_day',          5),
  ('trust_threshold',        3),
  ('saves_max',             50),
  ('likes_per_day',        300),
  ('reports_per_day',       20),
  ('report_hide_threshold',  3),
  ('nickname_change_days',   7),
  ('terms_version',          1)
on conflict (key) do nothing;

-- -----------------------------------------------------------------------------
-- profiles (base table, private schema)
-- -----------------------------------------------------------------------------
create table private.profiles (
  id                  uuid primary key references auth.users (id) on delete cascade,
  nickname            text not null check (char_length(nickname) between 1 and 24),
  avatar_post_id      uuid,
  terms_version       integer not null check (terms_version >= 1),
  terms_accepted_at   timestamptz not null default now(),
  -- NULL until the first nickname change; the 7-day cooldown is between changes.
  nickname_changed_at timestamptz,
  approved_count      integer not null default 0 check (approved_count >= 0),
  banned_at           timestamptz,
  created_at          timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- posts
-- -----------------------------------------------------------------------------
create table public.posts (
  id                uuid primary key default gen_random_uuid(),
  author_id         uuid not null references auth.users (id) on delete cascade,
  client_artwork_id uuid not null,
  status            text not null default 'uploading'
                    check (status in ('uploading', 'pending', 'public', 'hidden', 'removed')),
  kind              text not null
                    check (kind in ('sticker', 'graffiti', 'mural', 'poster', 'tag', 'other')),
  lat               double precision not null check (lat between -90 and 90),
  lng               double precision not null check (lng between -180 and 180),
  locality          text check (char_length(locality) <= 100),
  country_code      text check (country_code ~ '^[A-Z]{2}$'),
  captured_on       date,
  width             integer not null check (width between 1 and 8192),
  height            integer not null check (height between 1 and 8192),
  image_key         text not null,
  thumb_key         text not null,
  like_count        integer not null default 0 check (like_count >= 0),
  created_at        timestamptz not null default now(),
  published_at      timestamptz,
  -- Set by trigger when status becomes 'removed'; rows are purged 30 days later.
  removed_at        timestamptz
);

-- §4 unique(author_id, client_artwork_id): retries never create a second post.
-- Partial (ignores 'removed') so an author can publish the same artwork again
-- after retracting it; the new post gets a new id and therefore new image keys,
-- which keeps image URLs immutable (§7).
create unique index posts_author_artwork_key
  on public.posts (author_id, client_artwork_id) where status <> 'removed';
-- Viewport queries (explore) over public posts.
create index posts_public_lat_lng_idx on public.posts (lat, lng) where status = 'public';
-- Quota counting and "my posts".
create index posts_author_created_idx on public.posts (author_id, created_at desc);

alter table private.profiles
  add constraint profiles_avatar_post_id_fkey
  foreign key (avatar_post_id) references public.posts (id) on delete set null;

-- -----------------------------------------------------------------------------
-- likes / saves / blocks / reports
-- -----------------------------------------------------------------------------
create table public.likes (
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  post_id    uuid not null references public.posts (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);
create index likes_post_id_idx on public.likes (post_id);
create index likes_user_created_idx on public.likes (user_id, created_at);

create table public.saves (
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  post_id    uuid not null references public.posts (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);
create index saves_post_id_idx on public.saves (post_id);

create table public.blocks (
  blocker_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  blocked_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index blocks_blocked_id_idx on public.blocks (blocked_id);

create table public.reports (
  id          uuid primary key default gen_random_uuid(),
  -- Reports survive the reporter's account deletion.
  reporter_id uuid references auth.users (id) on delete set null,
  post_id     uuid not null references public.posts (id) on delete cascade,
  reason      text not null check (char_length(reason) between 1 and 32),
  note        text check (char_length(note) <= 500),
  created_at  timestamptz not null default now(),
  resolved_at timestamptz,
  resolution  text,
  unique (reporter_id, post_id)
);
create index reports_post_open_idx on public.reports (post_id) where resolved_at is null;
create index reports_reporter_created_idx on public.reports (reporter_id, created_at);

-- -----------------------------------------------------------------------------
-- public.profiles view (see header)
-- security_invoker = false on purpose: the view reads private.profiles with the
-- owner's rights and itself decides which columns the caller may see.
-- (Supabase's advisor flags definer views; this one is intentional.)
-- -----------------------------------------------------------------------------
create view public.profiles with (security_invoker = false) as
select
  p.id,
  p.nickname,
  p.avatar_post_id,
  case when p.id = (select auth.uid()) then p.terms_version       end as terms_version,
  case when p.id = (select auth.uid()) then p.terms_accepted_at   end as terms_accepted_at,
  case when p.id = (select auth.uid()) then p.nickname_changed_at end as nickname_changed_at,
  case when p.id = (select auth.uid()) then p.approved_count      end as approved_count,
  case when p.id = (select auth.uid()) then p.banned_at           end as banned_at,
  case when p.id = (select auth.uid()) then p.created_at          end as created_at
from private.profiles p;

-- -----------------------------------------------------------------------------
-- Private helpers
-- -----------------------------------------------------------------------------
create function private.config(config_key text)
returns integer
language plpgsql stable security definer set search_path = ''
as $$
declare
  v integer;
begin
  select q.value into v from public.quota_config q where q.key = config_key;
  if v is null then
    raise exception 'quota_config key % missing', config_key;
  end if;
  return v;
end;
$$;

-- Start of the current UTC day / month.
create function private.utc_day_start()
returns timestamptz language sql stable set search_path = ''
as $$ select date_trunc('day', now() at time zone 'UTC') at time zone 'UTC' $$;

create function private.utc_month_start()
returns timestamptz language sql stable set search_path = ''
as $$ select date_trunc('month', now() at time zone 'UTC') at time zone 'UTC' $$;

-- Used by the posts RLS policy: author not banned, and not blocked by the caller.
create function private.author_visible(author uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select not exists (
           select 1 from private.profiles pr
           where pr.id = author and pr.banned_at is not null)
     and not exists (
           select 1 from public.blocks b
           where b.blocker_id = (select auth.uid()) and b.blocked_id = author);
$$;

-- -----------------------------------------------------------------------------
-- Triggers
-- -----------------------------------------------------------------------------

-- likes: server timestamp + daily limit (§6 likes_per_day).
create function private.likes_before_insert()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  used integer;
begin
  new.created_at := now();
  -- A duplicate is not a new like (the insert will conflict, or be ignored with
  -- ON CONFLICT DO NOTHING / PostgREST resolution=ignore-duplicates): no limit check.
  if exists (select 1 from public.likes l where l.user_id = new.user_id and l.post_id = new.post_id) then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('likes:' || new.user_id::text, 0));
  select count(*) into used
  from public.likes l
  where l.user_id = new.user_id and l.created_at >= private.utc_day_start();
  if used >= private.config('likes_per_day') then
    raise exception 'daily like limit reached' using hint = 'likes_day';
  end if;
  return new;
end;
$$;

-- likes: keep posts.like_count in sync.
create function private.likes_after_change()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.posts p set like_count = p.like_count + 1 where p.id = new.post_id;
  elsif tg_op = 'DELETE' then
    update public.posts p set like_count = greatest(p.like_count - 1, 0) where p.id = old.post_id;
  end if;
  return null;
end;
$$;

-- saves: server timestamp + cap (§6 saves_max).
create function private.saves_before_insert()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  used integer;
begin
  new.created_at := now();
  -- Duplicate save: not a new save, no cap check (see likes_before_insert).
  if exists (select 1 from public.saves s where s.user_id = new.user_id and s.post_id = new.post_id) then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('saves:' || new.user_id::text, 0));
  select count(*) into used from public.saves s where s.user_id = new.user_id;
  if used >= private.config('saves_max') then
    raise exception 'saves are full' using hint = 'saves_full';
  end if;
  return new;
end;
$$;

-- blocks: server timestamp.
create function private.blocks_before_insert()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  new.created_at := now();
  return new;
end;
$$;

-- posts: stamp removed_at, clear avatar references to a removed post.
create function private.posts_before_update()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.status = 'removed' and old.status <> 'removed' then
    new.removed_at := now();
    update private.profiles pr set avatar_post_id = null where pr.avatar_post_id = new.id;
  elsif new.status <> 'removed' then
    new.removed_at := null;
  end if;
  return new;
end;
$$;

create trigger likes_before_insert before insert on public.likes
  for each row execute function private.likes_before_insert();
create trigger likes_after_insert after insert on public.likes
  for each row execute function private.likes_after_change();
create trigger likes_after_delete after delete on public.likes
  for each row execute function private.likes_after_change();
create trigger saves_before_insert before insert on public.saves
  for each row execute function private.saves_before_insert();
create trigger blocks_before_insert before insert on public.blocks
  for each row execute function private.blocks_before_insert();
create trigger posts_before_update before update of status on public.posts
  for each row execute function private.posts_before_update();

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------
alter table private.profiles   enable row level security;  -- no policies: only via view / definer functions
alter table public.quota_config enable row level security; -- no policies: clients use my_quota()
alter table public.posts       enable row level security;
alter table public.likes       enable row level security;
alter table public.saves       enable row level security;
alter table public.blocks      enable row level security;
alter table public.reports     enable row level security;  -- no policies: clients cannot read reports

-- posts: public + author not banned + author not blocked by me; or my own (except removed).
create policy posts_select_public on public.posts
  for select to anon, authenticated
  using (status = 'public' and private.author_visible(author_id));

create policy posts_select_own on public.posts
  for select to authenticated
  using (author_id = (select auth.uid()) and status <> 'removed');

-- likes / saves: own rows only; may only like / save posts the caller can see and that are public.
create policy likes_select_own on public.likes
  for select to authenticated using (user_id = (select auth.uid()));
create policy likes_insert_own on public.likes
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.posts p where p.id = post_id and p.status = 'public'));
create policy likes_delete_own on public.likes
  for delete to authenticated using (user_id = (select auth.uid()));

create policy saves_select_own on public.saves
  for select to authenticated using (user_id = (select auth.uid()));
create policy saves_insert_own on public.saves
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.posts p where p.id = post_id and p.status = 'public'));
create policy saves_delete_own on public.saves
  for delete to authenticated using (user_id = (select auth.uid()));

create policy blocks_select_own on public.blocks
  for select to authenticated using (blocker_id = (select auth.uid()));
create policy blocks_insert_own on public.blocks
  for insert to authenticated with check (blocker_id = (select auth.uid()));
create policy blocks_delete_own on public.blocks
  for delete to authenticated using (blocker_id = (select auth.uid()));

-- -----------------------------------------------------------------------------
-- RPC: upsert_profile (§5)
-- -----------------------------------------------------------------------------
create function public.upsert_profile(nickname text, terms_version integer)
returns public.profiles
language plpgsql security definer set search_path = ''
as $$
declare
  uid      uuid := auth.uid();
  v_nick   text := btrim(upsert_profile.nickname);
  v_terms  integer := upsert_profile.terms_version;
  existing private.profiles;
  result   public.profiles;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501', hint = 'not_authenticated';
  end if;
  if v_nick is null or char_length(v_nick) not between 1 and 24 or v_nick ~ '[[:cntrl:]]' then
    raise exception 'nickname must be 1-24 characters' using errcode = '22023', hint = 'invalid_argument';
  end if;
  if v_terms is null or v_terms < 1 or v_terms > private.config('terms_version') then
    raise exception 'unknown terms_version' using errcode = '22023', hint = 'invalid_argument';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('profile:' || uid::text, 0));
  select * into existing from private.profiles pr where pr.id = uid;

  if not found then
    insert into private.profiles (id, nickname, terms_version, terms_accepted_at)
    values (uid, v_nick, v_terms, now());
  else
    if existing.banned_at is not null then
      raise exception 'banned' using hint = 'banned';
    end if;
    if v_nick <> existing.nickname then
      if existing.nickname_changed_at is not null
         and existing.nickname_changed_at
             > now() - make_interval(days => private.config('nickname_change_days')) then
        raise exception 'nickname can be changed once every % days',
          private.config('nickname_change_days') using hint = 'nickname_cooldown';
      end if;
      update private.profiles pr
         set nickname = v_nick, nickname_changed_at = now()
       where pr.id = uid;
    end if;
    -- Never downgrade an accepted terms version.
    if v_terms > existing.terms_version then
      update private.profiles pr
         set terms_version = v_terms, terms_accepted_at = now()
       where pr.id = uid;
    end if;
  end if;

  select * into result from public.profiles v where v.id = uid;
  return result;
end;
$$;

-- -----------------------------------------------------------------------------
-- RPC: create_post (§5)
-- Quota: counts every post CREATED in the UTC day / month window, whatever its
-- status — retracting (removed) does not refund quota.
-- -----------------------------------------------------------------------------
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
declare
  uid       uuid := auth.uid();
  prof      private.profiles;
  existing  public.posts;
  v_id      uuid;
  v_country text := upper(nullif(btrim(create_post.country_code), ''));
  v_local   text := nullif(btrim(create_post.locality), '');
  used      integer;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501', hint = 'not_authenticated';
  end if;

  select * into prof from private.profiles pr where pr.id = uid;
  if not found then
    raise exception 'profile required' using hint = 'profile_required';
  end if;
  if prof.banned_at is not null then
    raise exception 'banned' using hint = 'banned';
  end if;
  if create_post.client_artwork_id is null then
    raise exception 'client_artwork_id is required' using errcode = '22023', hint = 'invalid_argument';
  end if;

  -- Serialise per author: idempotency check + quota count + insert.
  perform pg_advisory_xact_lock(hashtextextended('posts:' || uid::text, 0));

  select * into existing
  from public.posts p
  where p.author_id = uid
    and p.client_artwork_id = create_post.client_artwork_id
    and p.status <> 'removed';
  if found then
    return jsonb_build_object(
      'post_id', existing.id, 'status', existing.status,
      'image_key', existing.image_key, 'thumb_key', existing.thumb_key);
  end if;

  if prof.terms_version < private.config('terms_version') then
    raise exception 'current terms not accepted' using hint = 'terms_required';
  end if;

  if create_post.kind is null
     or create_post.kind not in ('sticker', 'graffiti', 'mural', 'poster', 'tag', 'other') then
    raise exception 'invalid kind' using errcode = '22023', hint = 'invalid_argument';
  end if;
  if create_post.lat is null or create_post.lng is null
     or not (create_post.lat between -90 and 90)
     or not (create_post.lng between -180 and 180) then
    raise exception 'invalid coordinate' using errcode = '22023', hint = 'invalid_argument';
  end if;
  if create_post.width is null or create_post.height is null
     or create_post.width not between 1 and 8192 or create_post.height not between 1 and 8192 then
    raise exception 'invalid width / height' using errcode = '22023', hint = 'invalid_argument';
  end if;
  if v_country is not null and v_country !~ '^[A-Z]{2}$' then
    raise exception 'invalid country_code' using errcode = '22023', hint = 'invalid_argument';
  end if;
  if v_local is not null and char_length(v_local) > 100 then
    raise exception 'locality too long' using errcode = '22023', hint = 'invalid_argument';
  end if;

  select count(*) into used from public.posts p
  where p.author_id = uid and p.created_at >= private.utc_month_start();
  if used >= private.config('posts_per_month') then
    raise exception 'monthly post quota reached' using hint = 'quota_month';
  end if;

  select count(*) into used from public.posts p
  where p.author_id = uid and p.created_at >= private.utc_day_start();
  if used >= private.config('posts_per_day') then
    raise exception 'daily post quota reached' using hint = 'quota_day';
  end if;

  v_id := gen_random_uuid();
  insert into public.posts (
    id, author_id, client_artwork_id, status, kind, lat, lng, locality, country_code,
    captured_on, width, height, image_key, thumb_key)
  values (
    v_id, uid, create_post.client_artwork_id, 'uploading', create_post.kind,
    -- §4: re-snap to the 0.001° grid (~100 m); never trust the client.
    round(create_post.lat::numeric, 3)::double precision,
    round(create_post.lng::numeric, 3)::double precision,
    v_local, v_country, create_post.captured_on, create_post.width, create_post.height,
    'posts/' || v_id::text || '/full.heic',
    'posts/' || v_id::text || '/thumb.heic');

  return jsonb_build_object(
    'post_id', v_id, 'status', 'uploading',
    'image_key', 'posts/' || v_id::text || '/full.heic',
    'thumb_key', 'posts/' || v_id::text || '/thumb.heic');
end;
$$;

-- -----------------------------------------------------------------------------
-- RPC: explore (§5)
-- Security invoker: the posts RLS policy applies (banned / blocked authors hidden).
-- min_lng > max_lng is treated as a viewport crossing the antimeridian.
-- cell_deg > 0: one row per grid cell (latest post of the cell + cell_count),
--               at most 500 cells, most populated first.
-- otherwise:    at most 200 posts, newest first, cell_count = 1.
-- -----------------------------------------------------------------------------
create function public.explore(
  min_lat  double precision,
  min_lng  double precision,
  max_lat  double precision,
  max_lng  double precision,
  cell_deg double precision default 0
)
returns table (
  id              uuid,
  author_id       uuid,
  author_nickname text,
  kind            text,
  lat             double precision,
  lng             double precision,
  locality        text,
  country_code    text,
  captured_on     date,
  width           integer,
  height          integer,
  image_key       text,
  thumb_key       text,
  like_count      integer,
  published_at    timestamptz,
  cell_count      integer
)
language sql stable security invoker set search_path = ''
as $$
  with v as (
    select p.id, p.author_id, p.kind, p.lat, p.lng, p.locality, p.country_code,
           p.captured_on, p.width, p.height, p.image_key, p.thumb_key,
           p.like_count, p.published_at
    from public.posts p
    where p.status = 'public'
      and p.lat between explore.min_lat and explore.max_lat
      and (   (explore.min_lng <= explore.max_lng
               and p.lng between explore.min_lng and explore.max_lng)
           or (explore.min_lng >  explore.max_lng
               and (p.lng >= explore.min_lng or p.lng <= explore.max_lng)))
  ),
  listed as (
    select v.*, 1 as cell_count
    from v
    where coalesce(explore.cell_deg, 0) <= 0
    order by v.published_at desc nulls last, v.id
    limit 200
  ),
  ranked as (
    select v.*,
           count(*) over w as cell_count,
           row_number() over (w order by v.published_at desc nulls last, v.id) as rn
    from v
    where explore.cell_deg > 0
    window w as (partition by floor(v.lat / nullif(explore.cell_deg, 0)),
                              floor(v.lng / nullif(explore.cell_deg, 0)))
  ),
  cells as (
    select r.id, r.author_id, r.kind, r.lat, r.lng, r.locality, r.country_code,
           r.captured_on, r.width, r.height, r.image_key, r.thumb_key,
           r.like_count, r.published_at, r.cell_count::integer as cell_count
    from ranked r
    where r.rn = 1
    order by r.cell_count desc, r.published_at desc nulls last
    limit 500
  ),
  merged as (
    select * from listed
    union all
    select * from cells
  )
  select m.id, m.author_id, pr.nickname, m.kind, m.lat, m.lng, m.locality, m.country_code,
         m.captured_on, m.width, m.height, m.image_key, m.thumb_key, m.like_count,
         m.published_at, m.cell_count
  from merged m
  left join public.profiles pr on pr.id = m.author_id
  order by m.cell_count desc, m.published_at desc nulls last, m.id;
$$;

-- -----------------------------------------------------------------------------
-- RPC: report_post (§5)
-- The post must be public or already hidden (blocks are ignored so that
-- "block, then report" works). Re-reporting is a no-op returning ok and does
-- not use daily quota. Distinct open reports >= report_hide_threshold hide a
-- public post.
-- -----------------------------------------------------------------------------
create function public.report_post(post_id uuid, reason text, note text default null)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  uid     uuid := auth.uid();
  v_post  public.posts;
  v_note  text := nullif(btrim(report_post.note), '');
  used    integer;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501', hint = 'not_authenticated';
  end if;
  if report_post.reason is null or char_length(report_post.reason) not between 1 and 32 then
    raise exception 'invalid reason' using errcode = '22023', hint = 'invalid_argument';
  end if;
  if v_note is not null and char_length(v_note) > 500 then
    raise exception 'note too long' using errcode = '22023', hint = 'invalid_argument';
  end if;

  select * into v_post from public.posts p
  where p.id = report_post.post_id and p.status in ('public', 'hidden')
  for update;
  if not found then
    raise exception 'post not found' using errcode = 'P0002', hint = 'not_found';
  end if;

  if exists (select 1 from public.reports r
             where r.reporter_id = uid and r.post_id = v_post.id) then
    return jsonb_build_object('ok', true);
  end if;

  perform pg_advisory_xact_lock(hashtextextended('reports:' || uid::text, 0));
  select count(*) into used from public.reports r
  where r.reporter_id = uid and r.created_at >= private.utc_day_start();
  if used >= private.config('reports_per_day') then
    raise exception 'daily report limit reached' using hint = 'reports_day';
  end if;

  insert into public.reports (reporter_id, post_id, reason, note)
  values (uid, v_post.id, report_post.reason, v_note);

  if v_post.status = 'public' then
    select count(*) into used from public.reports r
    where r.post_id = v_post.id and r.resolved_at is null;
    if used >= private.config('report_hide_threshold') then
      update public.posts p set status = 'hidden' where p.id = v_post.id;
    end if;
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

-- -----------------------------------------------------------------------------
-- RPC: my_quota (§5). resets_at = start of next UTC month.
-- Counts posts created in the window regardless of status (same rule as create_post).
-- -----------------------------------------------------------------------------
create function public.my_quota()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  month_used integer;
  day_used integer;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501', hint = 'not_authenticated';
  end if;
  select count(*) into month_used from public.posts p
  where p.author_id = uid and p.created_at >= private.utc_month_start();
  select count(*) into day_used from public.posts p
  where p.author_id = uid and p.created_at >= private.utc_day_start();
  return jsonb_build_object(
    'month_used',  month_used,
    'month_limit', private.config('posts_per_month'),
    'day_used',    day_used,
    'day_limit',   private.config('posts_per_day'),
    -- Month arithmetic done on UTC wall-clock time so the session TimeZone cannot shift it.
    'resets_at',   (date_trunc('month', now() at time zone 'UTC') + interval '1 month') at time zone 'UTC');
end;
$$;

-- -----------------------------------------------------------------------------
-- Service role only: complete_post_upload (§5, called by the Worker)
-- uploading -> public (author trusted) / pending. Idempotent: a post that has
-- already left 'uploading' is returned unchanged; 'removed' is refused.
-- -----------------------------------------------------------------------------
create function public.complete_post_upload(post_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_post   public.posts;
  prof     private.profiles;
  v_status text;
begin
  select * into v_post from public.posts p where p.id = complete_post_upload.post_id for update;
  if not found then
    raise exception 'post not found' using errcode = 'P0002', hint = 'not_found';
  end if;
  select * into prof from private.profiles pr where pr.id = v_post.author_id;
  if prof.banned_at is not null then
    raise exception 'banned' using hint = 'banned';
  end if;
  if v_post.status = 'removed' then
    raise exception 'post was removed' using errcode = '55000', hint = 'invalid_status';
  end if;
  if v_post.status <> 'uploading' then
    return jsonb_build_object('post_id', v_post.id, 'status', v_post.status);
  end if;

  if coalesce(prof.approved_count, 0) >= private.config('trust_threshold') then
    v_status := 'public';
    update public.posts p set status = 'public', published_at = now() where p.id = v_post.id;
  else
    v_status := 'pending';
    update public.posts p set status = 'pending' where p.id = v_post.id;
  end if;
  return jsonb_build_object('post_id', v_post.id, 'status', v_status);
end;
$$;

-- -----------------------------------------------------------------------------
-- Service role only: moderate_post (§5; run from the SQL editor for MVP)
--   approve: pending / hidden -> public, author approved_count + 1, open reports dismissed.
--            Already public: no-op.
--   reject:  pending / public / hidden -> hidden, open reports upheld.
-- -----------------------------------------------------------------------------
create function public.moderate_post(post_id uuid, decision text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_post public.posts;
begin
  if moderate_post.decision is null or moderate_post.decision not in ('approve', 'reject') then
    raise exception 'decision must be approve or reject' using errcode = '22023', hint = 'invalid_argument';
  end if;
  select * into v_post from public.posts p where p.id = moderate_post.post_id for update;
  if not found then
    raise exception 'post not found' using errcode = 'P0002', hint = 'not_found';
  end if;

  if moderate_post.decision = 'approve' then
    if v_post.status in ('pending', 'hidden') then
      update public.posts p
         set status = 'public', published_at = coalesce(p.published_at, now())
       where p.id = v_post.id;
      update private.profiles pr set approved_count = pr.approved_count + 1
       where pr.id = v_post.author_id;
      update public.reports r set resolved_at = now(), resolution = 'dismissed'
       where r.post_id = v_post.id and r.resolved_at is null;
      return jsonb_build_object('post_id', v_post.id, 'status', 'public');
    elsif v_post.status = 'public' then
      return jsonb_build_object('post_id', v_post.id, 'status', 'public');
    end if;
  else
    if v_post.status in ('pending', 'public', 'hidden') then
      update public.posts p set status = 'hidden' where p.id = v_post.id;
      update public.reports r set resolved_at = now(), resolution = 'upheld'
       where r.post_id = v_post.id and r.resolved_at is null;
      return jsonb_build_object('post_id', v_post.id, 'status', 'hidden');
    end if;
  end if;

  raise exception 'cannot moderate a post in status %', v_post.status
    using errcode = '55000', hint = 'invalid_status';
end;
$$;

-- -----------------------------------------------------------------------------
-- Grants (explicit and minimal)
-- -----------------------------------------------------------------------------
revoke all on table
  public.quota_config, public.posts, public.likes, public.saves, public.blocks,
  public.reports, public.profiles
  from public, anon, authenticated;
revoke all on all tables in schema private from public, anon, authenticated;

grant select on public.profiles to anon, authenticated;
grant select on public.posts    to anon, authenticated;
grant select, insert, delete on public.likes, public.saves, public.blocks to authenticated;

-- service_role (the Worker; bypasses RLS). It reaches private data only via the
-- view and the functions below.
grant select on public.profiles to service_role;
grant select, insert, update, delete on
  public.quota_config, public.posts, public.likes, public.saves, public.blocks, public.reports
  to service_role;

-- Functions: Postgres grants EXECUTE to PUBLIC by default and Supabase adds
-- anon / authenticated / service_role for public functions; reset all of them.
revoke all on all functions in schema private from public, anon, authenticated;
grant execute on function private.author_visible(uuid) to anon, authenticated;

revoke all on function public.upsert_profile(text, integer)                    from public, anon, authenticated;
revoke all on function public.create_post(uuid, text, double precision, double precision, text, text, date, integer, integer)
                                                                               from public, anon, authenticated;
revoke all on function public.explore(double precision, double precision, double precision, double precision, double precision)
                                                                               from public, anon, authenticated;
revoke all on function public.report_post(uuid, text, text)                    from public, anon, authenticated;
revoke all on function public.my_quota()                                       from public, anon, authenticated;
revoke all on function public.complete_post_upload(uuid)                       from public, anon, authenticated;
revoke all on function public.moderate_post(uuid, text)                        from public, anon, authenticated;

grant execute on function public.upsert_profile(text, integer) to authenticated;
grant execute on function public.create_post(uuid, text, double precision, double precision, text, text, date, integer, integer)
  to authenticated;
grant execute on function public.explore(double precision, double precision, double precision, double precision, double precision)
  to anon, authenticated;
grant execute on function public.report_post(uuid, text, text) to authenticated;
grant execute on function public.my_quota() to authenticated;

grant execute on function public.complete_post_upload(uuid) to service_role;
grant execute on function public.moderate_post(uuid, text)  to service_role;
