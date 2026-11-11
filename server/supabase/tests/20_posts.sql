-- create_post, quotas, my_quota, posts RLS for authors
begin;

select tests.make_profile('00000000-0000-0000-0000-00000000000a', 'alice');
select tests.make_profile('00000000-0000-0000-0000-00000000000b', 'bob');
select tests.make_profile('00000000-0000-0000-0000-00000000000d', 'dave');
select tests.make_profile('00000000-0000-0000-0000-00000000000e', 'erin');
select tests.make_profile('00000000-0000-0000-0000-00000000000f', 'frank', banned => true);
-- dave already used his month: 20 posts at the start of this UTC month
select tests.make_post('00000000-0000-0000-0000-00000000000d',
                       created => (date_trunc('month', now() at time zone 'UTC') at time zone 'UTC') + interval '1 minute')
from generate_series(1, 20);

-- anon / no profile / banned
set role anon; select tests.claims(null);
select tests.throws_state($$ select public.create_post('10000000-0000-0000-0000-000000000001', 'sticker', 35, 139, width => 10, height => 10) $$,
                          '42501', 'anon cannot call create_post');
select tests.throws_state($$ select public.my_quota() $$, '42501', 'anon cannot call my_quota');
reset role;

set role authenticated;
select tests.claims('00000000-0000-0000-0000-00000000000c');
select tests.throws_hint($$ select public.create_post('10000000-0000-0000-0000-000000000001', 'sticker', 35, 139, width => 10, height => 10) $$,
                         'profile_required', 'create_post without profile refused');
select tests.claims('00000000-0000-0000-0000-00000000000f');
select tests.throws_hint($$ select public.create_post('10000000-0000-0000-0000-000000000001', 'sticker', 35, 139, width => 10, height => 10) $$,
                         'banned', 'banned author refused');
select tests.claims('00000000-0000-0000-0000-00000000000d');
select tests.throws_hint($$ select public.create_post('10000000-0000-0000-0000-000000000001', 'sticker', 35, 139, width => 10, height => 10) $$,
                         'quota_month', 'monthly quota (20) refused');

-- alice: first post; optional params omitted (named notation, like PostgREST)
select tests.claims('00000000-0000-0000-0000-00000000000a');
insert into tests.ids
select 'p1', (public.create_post(client_artwork_id => '10000000-0000-0000-0000-000000000001', kind => 'sticker',
                                 lat => 35.68149, lng => 139.76751, width => 1024, height => 768) ->> 'post_id')::uuid;
select tests.ok((select status = 'uploading' and lat = 35.681 and lng = 139.768
                        and image_key = 'posts/' || id || '/full.heic' and thumb_key = 'posts/' || id || '/thumb.heic'
                        and locality is null and captured_on is null
                 from public.posts where id = tests.id('p1')),
                'post created as uploading, coordinates re-snapped to 0.001, keys derived from id');
select tests.eq(public.create_post('10000000-0000-0000-0000-000000000001', 'mural', 1, 1, 'X', 'jp', '2026-01-01', 1, 1) ->> 'post_id',
                tests.id('p1')::text, 'same client_artwork_id returns the existing post');
select tests.eq((select count(*) from public.posts where author_id = auth.uid())::int, 1, 'retry did not create a second post');
select tests.eq((public.my_quota() ->> 'day_used')::int, 1, 'retry did not consume quota');
select tests.throws_hint($$ select public.create_post(gen_random_uuid(), 'spaceship', 35, 139, width => 10, height => 10) $$,
                         'invalid_argument', 'unknown kind rejected');
select tests.throws_hint($$ select public.create_post(gen_random_uuid(), 'sticker', 91, 139, width => 10, height => 10) $$,
                         'invalid_argument', 'latitude out of range rejected');
select tests.throws_hint($$ select public.create_post(gen_random_uuid(), 'sticker', 35, 139) $$,
                         'invalid_argument', 'missing width/height rejected');
insert into tests.ids
select 'p2', (public.create_post(gen_random_uuid(), 'tag', -33.86851, -151.20949, ' Shibuya ', 'jp', '2026-11-01', 400, 300) ->> 'post_id')::uuid;
select tests.ok((select country_code = 'JP' and locality = 'Shibuya' and lat = -33.869 and lng = -151.209
                 from public.posts where id = tests.id('p2')),
                'country code upper-cased, locality trimmed, negative coordinates snapped');

-- author sees own uploading/pending posts; others and anon do not
select tests.eq((select count(*) from public.posts where author_id = auth.uid())::int, 2, 'author sees own uploading posts');
select tests.claims('00000000-0000-0000-0000-00000000000b');
select tests.eq((select count(*) from public.posts where author_id = '00000000-0000-0000-0000-00000000000a')::int, 0,
                'other users do not see uploading posts');
select tests.throws_state($$ insert into public.posts (author_id, client_artwork_id, kind, lat, lng, width, height, image_key, thumb_key)
                             values ('00000000-0000-0000-0000-00000000000b', gen_random_uuid(), 'sticker', 0, 0, 1, 1, 'a', 'b') $$,
                          '42501', 'clients cannot insert posts directly');
select tests.throws_state($$ update public.posts set status = 'public' $$, '42501', 'clients cannot update posts');
select tests.throws_state($$ delete from public.posts $$, '42501', 'clients cannot delete posts');
reset role;
set role anon; select tests.claims(null);
select tests.eq((select count(*) from public.posts)::int, 20, 'anon sees only public posts (dave''s 20)');
reset role;

-- daily quota: alice has 2 today, 3 more are allowed, the 6th is refused
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000a');
select public.create_post(gen_random_uuid(), 'sticker', 35, 139, width => 10, height => 10) from generate_series(1, 3);
select tests.throws_hint($$ select public.create_post(gen_random_uuid(), 'sticker', 35, 139, width => 10, height => 10) $$,
                         'quota_day', 'sixth post of the UTC day refused');
select tests.eq(public.create_post('10000000-0000-0000-0000-000000000001', 'sticker', 35, 139, width => 10, height => 10) ->> 'post_id',
                tests.id('p1')::text, 'retry of an existing post still works when quota is exhausted');
select tests.ok((select (q ->> 'day_used')::int = 5 and (q ->> 'day_limit')::int = 5
                        and (q ->> 'month_used')::int = 5 and (q ->> 'month_limit')::int = 20
                        and (q ->> 'resets_at')::timestamptz
                            = (date_trunc('month', now() at time zone 'UTC') + interval '1 month') at time zone 'UTC'
                 from public.my_quota() q),
                'my_quota reports usage, limits and next UTC month start');
reset role;

-- retracting does not refund quota
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000b');
insert into tests.ids
select 'b1', (public.create_post('20000000-0000-0000-0000-000000000001', 'sticker', 35, 139, width => 10, height => 10) ->> 'post_id')::uuid;
reset role;
set role service_role; select tests.claims(null);
update public.posts set status = 'removed' where id = tests.id('b1');   -- what the Worker does on DELETE /v1/posts/{id}
reset role;
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000b');
select tests.eq((select count(*) from public.posts where author_id = auth.uid())::int, 0, 'author no longer sees a removed post');
select tests.eq((public.my_quota() ->> 'day_used')::int, 1, 'retracted post still counts toward the daily quota');
select tests.eq((public.my_quota() ->> 'month_used')::int, 1, 'retracted post still counts toward the monthly quota');
insert into tests.ids
select 'b2', (public.create_post('20000000-0000-0000-0000-000000000001', 'sticker', 35, 139, width => 10, height => 10) ->> 'post_id')::uuid;
select tests.ok(tests.id('b2') <> tests.id('b1'), 'republishing a retracted artwork creates a new post (new id, new image keys)');
select tests.eq((public.my_quota() ->> 'day_used')::int, 2, 'republishing consumes quota again');
select public.create_post(gen_random_uuid(), 'sticker', 35, 139, width => 10, height => 10) from generate_series(1, 3);
select tests.throws_hint($$ select public.create_post(gen_random_uuid(), 'sticker', 35, 139, width => 10, height => 10) $$,
                         'quota_day', 'removed posts are counted: quota_day after 4 live + 1 removed');
reset role;

-- terms
update public.quota_config set value = 2 where key = 'terms_version';
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000e');
select tests.throws_hint($$ select public.create_post(gen_random_uuid(), 'sticker', 35, 139, width => 10, height => 10) $$,
                         'terms_required', 'new terms version must be accepted before posting');
select public.upsert_profile('erin', 2);
select tests.eq(public.create_post(gen_random_uuid(), 'sticker', 35, 139, width => 10, height => 10) ->> 'status',
                'uploading', 'posting works after accepting new terms');
reset role;

rollback;
