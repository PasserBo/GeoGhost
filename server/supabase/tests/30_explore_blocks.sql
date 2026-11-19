-- explore + posts visibility (anon, banned authors, blocks)
begin;

select tests.make_profile('00000000-0000-0000-0000-00000000000a', 'alice');
select tests.make_profile('00000000-0000-0000-0000-00000000000b', 'bob');
select tests.make_profile('00000000-0000-0000-0000-00000000000c', 'carol', banned => true);

insert into tests.ids values
  ('a1',    tests.make_post('00000000-0000-0000-0000-00000000000a', 'public',  35.681, 139.768, published => now() - interval '1 hour')),
  ('a2',    tests.make_post('00000000-0000-0000-0000-00000000000a', 'public',  35.682, 139.769, published => now())),
  ('a3',    tests.make_post('00000000-0000-0000-0000-00000000000a', 'pending', 35.681, 139.768)),
  ('a4',    tests.make_post('00000000-0000-0000-0000-00000000000a', 'hidden',  35.681, 139.768)),
  ('a5',    tests.make_post('00000000-0000-0000-0000-00000000000a', 'removed', 35.681, 139.768)),
  ('a6',    tests.make_post('00000000-0000-0000-0000-00000000000a', 'uploading', 35.681, 139.768)),
  ('b1',    tests.make_post('00000000-0000-0000-0000-00000000000b', 'public',  35.700, 139.700, published => now() - interval '2 hours')),
  ('bfar',  tests.make_post('00000000-0000-0000-0000-00000000000b', 'public',  10, 10)),
  ('beast', tests.make_post('00000000-0000-0000-0000-00000000000b', 'public',  0, 179.5)),
  ('bwest', tests.make_post('00000000-0000-0000-0000-00000000000b', 'public',  0, -179.5)),
  ('c1',    tests.make_post('00000000-0000-0000-0000-00000000000c', 'public',  35.690, 139.750));

-- anon
set role anon; select tests.claims(null);
select tests.eq((select count(*) from public.posts)::int, 6, 'anon reads only public posts of non-banned authors');
select tests.eq((select count(*) from public.posts where id = tests.id('c1'))::int, 0, 'banned author''s public post invisible');
select tests.eq((select array_agg(id order by published_at desc) from public.explore(35.6, 139.6, 35.8, 139.8)),
                array[tests.id('a2'), tests.id('a1'), tests.id('b1')], 'explore list: viewport, public only, newest first');
select tests.ok((select bool_and(cell_count = 1) and bool_and(author_nickname is not null)
                 from public.explore(35.6, 139.6, 35.8, 139.8, 0)), 'list mode: cell_count = 1, author nickname included');
select tests.ok((select count(*) = 2
                        and max(cell_count) = 2
                        and (array_agg(id order by cell_count desc))[1] = tests.id('a2')
                 from public.explore(35.6, 139.6, 35.8, 139.8, 0.01)),
                'grid mode: one row per cell with count and the latest post');
select tests.eq((select count(*) from public.explore(-1, 179, 1, -179))::int, 2, 'viewport crossing the antimeridian');
select tests.eq((select count(*) from public.explore(-90, -180, 90, 180))::int, 6, 'world viewport');
select tests.throws_state($$ select * from public.likes $$, '42501', 'anon cannot read likes');
select tests.throws_state($$ select * from public.blocks $$, '42501', 'anon cannot read blocks');
reset role;

-- 200 cap in list mode
select tests.make_post('00000000-0000-0000-0000-00000000000b', 'public', 50, 50) from generate_series(1, 210);
set role anon; select tests.claims(null);
select tests.eq((select count(*) from public.explore(49, 49, 51, 51))::int, 200, 'list mode returns at most 200 posts');
select tests.eq((select sum(cell_count) from public.explore(49, 49, 51, 51, 1))::int, 210, 'grid mode counts all posts');
reset role;

-- author sees own non-public posts (except removed); explore stays public-only
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000a');
select tests.eq((select array_agg(status order by status) from public.posts where author_id = auth.uid()),
                array['hidden', 'pending', 'public', 'public', 'uploading'], 'author sees own uploading / pending / hidden, not removed');
select tests.eq((select count(*) from public.explore(35.6, 139.6, 35.8, 139.8))::int, 3, 'explore never returns pending posts, even to the author');
reset role;

-- blocks
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000b');
insert into public.blocks (blocked_id) values ('00000000-0000-0000-0000-00000000000a');
select tests.eq((select count(*) from public.posts where author_id = '00000000-0000-0000-0000-00000000000a')::int, 0,
                'blocked author''s posts invisible to the blocker');
select tests.eq((select count(*) from public.explore(35.6, 139.6, 35.8, 139.8))::int, 1, 'explore hides blocked author');
select tests.eq((select count(*) from public.blocks)::int, 1, 'blocker reads own block');
select tests.throws_state($$ insert into public.blocks (blocker_id, blocked_id) values ('00000000-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-00000000000a') $$,
                          '42501', 'cannot insert a block on behalf of someone else');
select tests.throws_state($$ insert into public.blocks (blocked_id) values ('00000000-0000-0000-0000-00000000000b') $$,
                          '23514', 'cannot block yourself');
select tests.throws_state($$ update public.blocks set blocked_id = '00000000-0000-0000-0000-00000000000c' $$,
                          '42501', 'blocks are not updatable');
select tests.claims('00000000-0000-0000-0000-00000000000a');
select tests.eq((select count(*) from public.blocks)::int, 0, 'blocked user cannot read the blocker''s blocks');
delete from public.blocks;   -- RLS: deletes nothing that is not alice's
select tests.eq((select count(*) from public.explore(35.6, 139.6, 35.8, 139.8))::int, 3, 'block is one-directional');
reset role;
set role anon; select tests.claims(null);
select tests.eq((select count(*) from public.explore(35.6, 139.6, 35.8, 139.8))::int, 3, 'blocks do not affect anon');
reset role;
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000b');
select tests.eq((select count(*) from public.blocks)::int, 1, 'other users could not delete the block');
delete from public.blocks where blocked_id = '00000000-0000-0000-0000-00000000000a';
select tests.eq((select count(*) from public.explore(35.6, 139.6, 35.8, 139.8))::int, 3, 'unblocking shows the posts again');
reset role;

rollback;
