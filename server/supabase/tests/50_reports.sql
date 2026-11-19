-- report_post: idempotency, daily limit, hide threshold, reports not readable
begin;

select tests.make_profile('00000000-0000-0000-0000-00000000000a', 'alice');
insert into tests.ids values
  ('p',       tests.make_post('00000000-0000-0000-0000-00000000000a', 'public')),
  ('pending', tests.make_post('00000000-0000-0000-0000-00000000000a', 'pending'));

set role anon; select tests.claims(null);
select tests.throws_state($$ select public.report_post(tests.id('p'), 'spam') $$, '42501', 'anon cannot report');
reset role;

set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000b');
select tests.eq(public.report_post(tests.id('p'), 'spam', 'looks like an ad'), '{"ok": true}'::jsonb, 'report accepted (no profile needed)');
select tests.eq(public.report_post(tests.id('p'), 'other'), '{"ok": true}'::jsonb, 'repeat report returns ok');
select tests.throws_state($$ select * from public.reports $$, '42501', 'clients cannot read reports');
select tests.throws_state($$ insert into public.reports (reporter_id, post_id, reason) values (auth.uid(), tests.id('p'), 'x') $$,
                          '42501', 'clients cannot insert reports directly');
select tests.throws_hint($$ select public.report_post(tests.id('pending'), 'spam') $$, 'not_found', 'cannot report a post that is not visible');
select tests.throws_hint($$ select public.report_post(gen_random_uuid(), 'spam') $$, 'not_found', 'unknown post');
select tests.throws_hint($$ select public.report_post(tests.id('p'), '') $$, 'invalid_argument', 'empty reason rejected');
reset role;
select tests.eq((select count(*) from public.reports where post_id = tests.id('p'))::int, 1, 'same reporter counted once');

set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000c');
select public.report_post(tests.id('p'), 'spam');
reset role;
select tests.eq((select status from public.posts where id = tests.id('p')), 'public', 'two distinct reporters: still public');

-- the reporter has blocked the author: reporting still works
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000d');
insert into public.blocks (blocked_id) values ('00000000-0000-0000-0000-00000000000a');
select public.report_post(tests.id('p'), 'harassment');
reset role;
select tests.eq((select status from public.posts where id = tests.id('p')), 'pending', 'third distinct reporter hides the post (back into review, 20261112030000)');

set role anon; select tests.claims(null);
select tests.eq((select count(*) from public.posts where id = tests.id('p'))::int, 0, 'post in re-review invisible to others');
reset role;
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000a');
select tests.eq((select status from public.posts where id = tests.id('p')), 'pending', 'author still sees it, in review');
reset role;

-- moderator approves: open reports are resolved, a fresh set is needed to hide again
set role service_role; select tests.claims(null);
select public.moderate_post(tests.id('p'), 'approve');
reset role;
select tests.ok((select bool_and(resolved_at is not null and resolution = 'dismissed') from public.reports where post_id = tests.id('p')),
                'approval dismisses open reports');
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000e');
select public.report_post(tests.id('p'), 'spam');
reset role;
select tests.eq((select status from public.posts where id = tests.id('p')), 'public', 'resolved reports no longer count toward the threshold');

-- daily report limit: 20 per UTC day; re-reporting does not use quota
insert into tests.ids
select 'r' || g, tests.make_post('00000000-0000-0000-0000-00000000000a', 'public') from generate_series(1, 21) g;
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000f');
select public.report_post(id, 'spam') from tests.ids where name ~ '^r([1-9]|1[0-9]|20)$';
select tests.throws_hint($$ select public.report_post(tests.id('r21'), 'spam') $$, 'reports_day', '21st report of the UTC day refused');
select tests.eq(public.report_post(tests.id('r1'), 'spam'), '{"ok": true}'::jsonb, 'repeat report still ok after the limit');
reset role;
update public.reports set created_at = now() - interval '1 day' where reporter_id = '00000000-0000-0000-0000-00000000000f';
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000f');
select tests.eq(public.report_post(tests.id('r21'), 'spam'), '{"ok": true}'::jsonb, 'reports from previous days do not count');
reset role;

rollback;
