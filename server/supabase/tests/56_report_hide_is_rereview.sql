-- 3 distinct reporters put a public post back into review (pending, published_at kept), not hidden.
begin;

select tests.make_profile('00000000-0000-0000-0000-00000000000a', 'alice', approved => 3);
insert into tests.ids values
  ('p',   tests.make_post('00000000-0000-0000-0000-00000000000a', 'public', published => now() - interval '10 days',
                          created => now() - interval '10 days')),
  ('q',   tests.make_post('00000000-0000-0000-0000-00000000000a', 'public')),
  ('new', tests.make_post('00000000-0000-0000-0000-00000000000a', 'pending', created => now() - interval '1 hour'));

set role authenticated;
select tests.claims('00000000-0000-0000-0000-00000000000b'); select public.report_post(tests.id('p'), 'spam');
select tests.claims('00000000-0000-0000-0000-00000000000c'); select public.report_post(tests.id('p'), 'spam');
reset role;
select tests.eq((select status from public.posts where id = tests.id('p')), 'public', 'two reporters: still public');
set role authenticated;
select tests.claims('00000000-0000-0000-0000-00000000000d'); select public.report_post(tests.id('p'), 'privacy');
reset role;
select tests.eq((select status from public.posts where id = tests.id('p')), 'pending', 'third reporter: back into review, not hidden');
select tests.ok((select published_at is not null from public.posts where id = tests.id('p')), 're-review keeps published_at');

set role anon; select tests.claims(null);
select tests.eq((select count(*) from public.posts where id = tests.id('p'))::int, 0, 'others cannot see it while in review');
reset role;
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000a');
select tests.eq((select status from public.posts where id = tests.id('p')), 'pending', 'the author sees it as in review');
select tests.ok((select published_at is not null from public.posts where id = tests.id('p')),
                'the author can tell it is a re-review (published_at readable on their own post)');
reset role;

-- Console: in both queues; waiting time of a re-review starts at its first report, not at creation.
set role service_role; select tests.claims(null);
select tests.ok(exists (select 1 from public.admin_queue('pending') where id = tests.id('p') and published_at is not null),
                'in the pending queue, recognisable as re-review (published_at set)');
select tests.ok(exists (select 1 from public.admin_queue('reported') where id = tests.id('p') and open_reports = 3),
                'in the reported queue with its 3 reports');
select tests.eq((public.admin_stats() ->> 'pending_count')::int, 2, 'pending count includes the re-review');
select tests.ok((public.admin_stats() ->> 'oldest_pending_at')::timestamptz > now() - interval '2 hours',
                'oldest pending wait is the first-time post (1 h), not the re-review''s 10-day-old creation');

-- Approve: public again, reports dismissed, trust not counted twice.
select public.admin_moderate(tests.id('p'), 'approve', 'op@example.com');
reset role;
select tests.eq((select status from public.posts where id = tests.id('p')), 'public', 'approve: public again');
select tests.eq((select approved_count from private.profiles where id = '00000000-0000-0000-0000-00000000000a'), 3,
                'approving a re-review does not add to approved_count');
select tests.ok((select bool_and(resolution = 'dismissed') from public.reports where post_id = tests.id('p')), 'reports dismissed');
set role service_role; select tests.claims(null);
select public.moderate_post(tests.id('new'), 'approve');
reset role;
select tests.eq((select approved_count from private.profiles where id = '00000000-0000-0000-0000-00000000000a'), 4,
                'a first-time approval still counts');

-- Reject a re-review: hidden, reports upheld.
set role authenticated;
select tests.claims('00000000-0000-0000-0000-00000000000b'); select public.report_post(tests.id('q'), 'spam');
select tests.claims('00000000-0000-0000-0000-00000000000c'); select public.report_post(tests.id('q'), 'spam');
select tests.claims('00000000-0000-0000-0000-00000000000d'); select public.report_post(tests.id('q'), 'spam');
reset role;
set role service_role; select tests.claims(null);
select tests.eq(public.moderate_post(tests.id('q'), 'reject') ->> 'status', 'hidden', 'reject a re-review: hidden');
reset role;
select tests.ok((select bool_and(resolution = 'upheld') from public.reports where post_id = tests.id('q')), 'reports upheld');

rollback;

-- Keeping a still-public reported post closes its reports (console "保留（关闭举报）").
begin;
select tests.make_profile('00000000-0000-0000-0000-00000000000a', 'alice', approved => 3);
insert into tests.ids values ('k', tests.make_post('00000000-0000-0000-0000-00000000000a', 'public'));
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000b');
select public.report_post(tests.id('k'), 'spam');
reset role;
set role service_role; select tests.claims(null);
select tests.eq(public.admin_moderate(tests.id('k'), 'approve', 'op@example.com') ->> 'status', 'public', 'keep: stays public');
select tests.ok(not exists (select 1 from public.admin_queue('reported') where id = tests.id('k')), 'keep: leaves the reported queue');
reset role;
select tests.eq((select approved_count from private.profiles where id = '00000000-0000-0000-0000-00000000000a'), 3,
                'keep: no trust counted');
rollback;
