-- LOCAL TESTS ONLY. Shared fixtures, committed once; every test file runs in
-- its own transaction and rolls back.
--
-- Users (auth.users):
--   alice 00000000-0000-0000-0000-00000000000a
--   bob   00000000-0000-0000-0000-00000000000b
--   carol 00000000-0000-0000-0000-00000000000c
--   dave  00000000-0000-0000-0000-00000000000d
--   erin  00000000-0000-0000-0000-00000000000e
--   frank 00000000-0000-0000-0000-00000000000f

insert into auth.users (id) values
  ('00000000-0000-0000-0000-00000000000a'),
  ('00000000-0000-0000-0000-00000000000b'),
  ('00000000-0000-0000-0000-00000000000c'),
  ('00000000-0000-0000-0000-00000000000d'),
  ('00000000-0000-0000-0000-00000000000e'),
  ('00000000-0000-0000-0000-00000000000f');

-- Direct inserts bypassing the RPCs (run as the table owner).
create function tests.make_profile(uid uuid, nick text, approved integer default 0, banned boolean default false)
returns void language sql security definer set search_path = '' as $$
  insert into private.profiles (id, nickname, terms_version, approved_count, banned_at)
  values (uid, nick, 1, approved, case when banned then now() end);
$$;

create function tests.make_post(
  author uuid, st text default 'public',
  la double precision default 35.681, ln double precision default 139.768,
  created timestamptz default now(), published timestamptz default now())
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v uuid := gen_random_uuid();
begin
  insert into public.posts (id, author_id, client_artwork_id, status, kind, lat, lng,
                            width, height, image_key, thumb_key, created_at, published_at)
  values (v, author, gen_random_uuid(), st, 'sticker', la, ln, 1024, 768,
          'posts/' || v || '/full.heic', 'posts/' || v || '/thumb.heic', created,
          case when st = 'public' then published end);
  return v;
end $$;

-- Named ids shared between statements of one test file (psql variables do not
-- expand inside dollar-quoted strings).
create table tests.ids (name text primary key, id uuid not null);
grant all on tests.ids to public;
create function tests.id(n text) returns uuid language sql stable as $$
  select id from tests.ids where name = n
$$;
