-- likes (like_count, daily limit) and saves (cap)
begin;

select tests.make_profile('00000000-0000-0000-0000-00000000000a', 'alice');
select tests.make_profile('00000000-0000-0000-0000-00000000000b', 'bob');
insert into tests.ids values
  ('p',       tests.make_post('00000000-0000-0000-0000-00000000000b', 'public')),
  ('pending', tests.make_post('00000000-0000-0000-0000-00000000000b', 'pending'));

set role anon; select tests.claims(null);
select tests.throws_state($$ insert into public.likes (post_id) values ((select id from public.posts limit 1)) $$,
                          '42501', 'anon cannot like');
reset role;

set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000a');
insert into public.likes (post_id, created_at) values (tests.id('p'), now() - interval '3 days');
select tests.eq((select like_count from public.posts where id = tests.id('p')), 1, 'like increments like_count');
select tests.ok((select created_at = now() and user_id = auth.uid() from public.likes),
                'like gets server user_id default and server timestamp');
select tests.throws_state($$ insert into public.likes (post_id) values (tests.id('p')) $$, '23505', 'cannot like twice');
select tests.eq((select like_count from public.posts where id = tests.id('p')), 1, 'failed double like leaves like_count unchanged');
select tests.throws_state($$ insert into public.likes (user_id, post_id) values ('00000000-0000-0000-0000-00000000000c', tests.id('p')) $$,
                          '42501', 'cannot like on behalf of someone else');
select tests.throws_state($$ insert into public.likes (post_id) values (tests.id('pending')) $$,
                          '42501', 'cannot like a post that is not public');
select tests.throws_state($$ update public.likes set post_id = tests.id('pending') $$, '42501', 'likes are not updatable');

select tests.claims('00000000-0000-0000-0000-00000000000b');
insert into public.likes (post_id) values (tests.id('p'));
select tests.eq((select like_count from public.posts where id = tests.id('p')), 2, 'second user''s like counted');
select tests.eq((select count(*) from public.likes)::int, 1, 'users read only their own likes');
delete from public.likes where post_id = tests.id('p');
select tests.eq((select like_count from public.posts where id = tests.id('p')), 1, 'unlike decrements like_count');

select tests.claims('00000000-0000-0000-0000-00000000000a');
delete from public.likes where user_id = '00000000-0000-0000-0000-00000000000b';  -- not alice's: RLS deletes nothing
select tests.eq((select like_count from public.posts where id = tests.id('p')), 1, 'cannot delete another user''s like');
reset role;

-- daily like limit: 300 per UTC day
insert into tests.ids
select 'bulk' || g, tests.make_post('00000000-0000-0000-0000-00000000000b', 'public') from generate_series(1, 400) g;
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000a');
insert into public.likes (post_id) select id from tests.ids where name like 'bulk%' and name <> 'bulk400' limit 299;
select tests.eq((select count(*) from public.likes)::int, 300, '300 likes today');
select tests.throws_hint($$ insert into public.likes (post_id) values (tests.id('bulk400')) $$, 'likes_day', '301st like of the UTC day refused');
insert into public.likes (post_id) values (tests.id('p')) on conflict do nothing;
select tests.ok(true, 'duplicate like with ON CONFLICT DO NOTHING (PostgREST ignore-duplicates) is not refused at the limit');
select tests.eq((select like_count from public.posts where id = tests.id('p')), 1, 'ignored duplicate like leaves like_count unchanged');
reset role;
update public.likes set created_at = now() - interval '1 day'
 where user_id = '00000000-0000-0000-0000-00000000000a' and post_id = tests.id('p');
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000a');
insert into public.likes (post_id) values (tests.id('bulk400'));
select tests.ok(true, 'likes from previous days do not count toward today');
select tests.eq((select sum(like_count) from public.posts where author_id = '00000000-0000-0000-0000-00000000000b')::int,
                (select count(*) from public.likes)::int, 'like_count totals match the likes table');
reset role;

-- saves: cap 50
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000a');
select tests.throws_state($$ insert into public.saves (post_id) values (tests.id('pending')) $$, '42501', 'cannot save a non-public post');
select tests.throws_state($$ insert into public.saves (user_id, post_id) values ('00000000-0000-0000-0000-00000000000b', tests.id('bulk399')) $$,
                          '42501', 'cannot save on behalf of someone else');
insert into public.saves (post_id) select id from tests.ids where name like 'bulk%' order by name limit 50;
select tests.eq((select count(*) from public.saves)::int, 50, '50 saves allowed');
select tests.throws_hint($$ insert into public.saves (post_id) values (tests.id('p')) $$, 'saves_full', '51st save refused');
insert into public.saves (post_id) select post_id from public.saves limit 1 on conflict do nothing;
select tests.eq((select count(*) from public.saves)::int, 50, 'duplicate save with ON CONFLICT DO NOTHING is not refused when full');
delete from public.saves where post_id = (select post_id from public.saves limit 1);
insert into public.saves (post_id) values (tests.id('p'));
select tests.eq((select count(*) from public.saves)::int, 50, 'saving works again after removing one');
select tests.claims('00000000-0000-0000-0000-00000000000b');
select tests.eq((select count(*) from public.saves)::int, 0, 'users read only their own saves');
reset role;

rollback;
