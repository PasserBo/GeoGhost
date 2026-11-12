-- A post the caller reported is hidden from the caller at once; others and anon still see it.
begin;

select tests.make_profile('00000000-0000-0000-0000-00000000000a', 'alice');
insert into tests.ids values
  ('p', tests.make_post('00000000-0000-0000-0000-00000000000a', 'public', 35.681, 139.768)),
  ('q', tests.make_post('00000000-0000-0000-0000-00000000000a', 'public', 35.682, 139.769));

set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000b');
select tests.eq((select count(*) from public.explore(35.6, 139.6, 35.8, 139.8))::int, 2, 'before reporting: both visible');
select public.report_post(tests.id('p'), 'spam');
select tests.eq((select array_agg(id) from public.explore(35.6, 139.6, 35.8, 139.8)), array[tests.id('q')],
                'reporter: reported post gone from explore (list mode)');
select tests.eq((select sum(cell_count) from public.explore(35.6, 139.6, 35.8, 139.8, 1))::int, 1,
                'reporter: not counted in grid cells either');
select tests.eq((select count(*) from public.posts where id = tests.id('p'))::int, 0, 'reporter: not readable directly');
select tests.throws_state($$ insert into public.likes (post_id) values (tests.id('p')) $$, '42501', 'reporter cannot like it');
select tests.eq(public.report_post(tests.id('p'), 'spam'), '{"ok": true}'::jsonb, 'reporting it again still returns ok');
reset role;

set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000c');
select tests.eq((select count(*) from public.explore(35.6, 139.6, 35.8, 139.8))::int, 2, 'another user still sees both');
reset role;

set role anon; select tests.claims(null);
select tests.eq((select count(*) from public.explore(35.6, 139.6, 35.8, 139.8))::int, 2, 'anon unaffected');
reset role;

set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000a');
select public.report_post(tests.id('q'), 'other', 'testing my own post');
select tests.eq((select count(*) from public.posts where id = tests.id('q'))::int, 1, 'the author still sees their own post');
reset role;

-- The operator approves: the post stays public for others, and stays gone for the reporter.
set role service_role; select tests.claims(null);
select public.moderate_post(tests.id('p'), 'approve');
reset role;
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000b');
select tests.eq((select count(*) from public.explore(35.6, 139.6, 35.8, 139.8))::int, 1, 'reporter: still gone after approval');
reset role;

rollback;
