-- Deleting the auth user (Worker: DELETE /v1/me -> admin API) cascades;
-- reports survive with reporter_id = null.
begin;

select tests.make_profile('00000000-0000-0000-0000-00000000000a', 'alice');
select tests.make_profile('00000000-0000-0000-0000-00000000000b', 'bob');
insert into tests.ids values
  ('a1', tests.make_post('00000000-0000-0000-0000-00000000000a', 'public')),
  ('b1', tests.make_post('00000000-0000-0000-0000-00000000000b', 'public'));

set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000a');
insert into public.likes (post_id) values (tests.id('b1'));
insert into public.saves (post_id) values (tests.id('b1'));
insert into public.blocks (blocked_id) values ('00000000-0000-0000-0000-00000000000c');
select public.report_post(tests.id('b1'), 'spam');
select tests.claims('00000000-0000-0000-0000-00000000000b');
insert into public.likes (post_id) values (tests.id('a1'));
insert into public.blocks (blocked_id) values ('00000000-0000-0000-0000-00000000000a');
select public.report_post(tests.id('a1'), 'spam');
reset role;

select tests.eq((select like_count from public.posts where id = tests.id('b1')), 1, 'precondition: bob''s post has 1 like');

delete from auth.users where id = '00000000-0000-0000-0000-00000000000a';

select tests.eq((select count(*) from private.profiles where id = '00000000-0000-0000-0000-00000000000a')::int, 0, 'profile deleted');
select tests.eq((select count(*) from public.posts where author_id = '00000000-0000-0000-0000-00000000000a')::int, 0, 'posts deleted');
select tests.eq((select count(*) from public.likes where user_id = '00000000-0000-0000-0000-00000000000a' or post_id = tests.id('a1'))::int, 0,
                'own likes and likes on own posts deleted');
select tests.eq((select count(*) from public.saves where user_id = '00000000-0000-0000-0000-00000000000a')::int, 0, 'saves deleted');
select tests.eq((select count(*) from public.blocks
                 where '00000000-0000-0000-0000-00000000000a' in (blocker_id, blocked_id))::int, 0, 'blocks by and of the user deleted');
select tests.eq((select like_count from public.posts where id = tests.id('b1')), 0, 'like_count of other posts kept right');
select tests.ok((select reporter_id is null from public.reports where post_id = tests.id('b1')),
                'reports by the deleted user kept with reporter_id = null');
select tests.eq((select count(*) from public.reports where post_id = tests.id('a1'))::int, 0,
                'reports about the deleted user''s posts go with the posts');

rollback;
