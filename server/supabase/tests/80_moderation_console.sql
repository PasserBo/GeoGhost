-- moderation console: admin_* functions (service role only) and the moderation log
begin;

select tests.make_profile('00000000-0000-0000-0000-00000000000a', 'alice');
select tests.make_profile('00000000-0000-0000-0000-00000000000b', 'bob', approved => 2);
insert into tests.ids values
  ('old',  tests.make_post('00000000-0000-0000-0000-00000000000a', 'pending', created => now() - interval '26 hours')),
  ('new',  tests.make_post('00000000-0000-0000-0000-00000000000a', 'pending', created => now() - interval '1 hour')),
  ('pub',  tests.make_post('00000000-0000-0000-0000-00000000000b', 'public')),
  ('hid',  tests.make_post('00000000-0000-0000-0000-00000000000b', 'hidden'));
insert into public.reports (reporter_id, post_id, reason, note, created_at) values
  ('00000000-0000-0000-0000-00000000000c', tests.id('pub'), 'spam', 'same sticker posted again', now() - interval '3 hours'),
  ('00000000-0000-0000-0000-00000000000d', tests.id('pub'), 'personal info', null, now() - interval '2 hours'),
  ('00000000-0000-0000-0000-00000000000e', tests.id('hid'), 'violence', null, now() - interval '5 hours');

-- Nobody but the service role.
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000a');
select tests.throws_state($$ select public.admin_stats() $$, '42501', 'authenticated cannot read admin_stats');
select tests.throws_state($$ select * from public.admin_queue('pending') $$, '42501', 'authenticated cannot read admin_queue');
select tests.throws_state($$ select public.admin_moderate(tests.id('old'), 'approve', 'me') $$, '42501', 'authenticated cannot moderate');
select tests.throws_state($$ select public.admin_set_ban('00000000-0000-0000-0000-00000000000b', true, 'me') $$, '42501', 'authenticated cannot ban');
reset role;
set role anon; select tests.claims(null);
select tests.throws_state($$ select * from public.admin_log() $$, '42501', 'anon cannot read the log');
select tests.throws_state($$ select public.admin_remove_post(tests.id('pub'), 'me') $$, '42501', 'anon cannot remove');
reset role;

set role service_role; select tests.claims(null);

-- Overview
select tests.eq((public.admin_stats() ->> 'pending_count')::int, 2, 'two posts wait for review');
select tests.ok((public.admin_stats() ->> 'oldest_pending_at')::timestamptz < now() - interval '25 hours', 'oldest pending is 26 hours old');
select tests.eq((public.admin_stats() ->> 'reported_count')::int, 2, 'two posts have open reports');

-- Queues
select tests.eq((select array_agg(id order by created_at) from public.admin_queue('pending')),
                array[tests.id('old'), tests.id('new')], 'pending queue: oldest first');
select tests.eq((select author_nickname from public.admin_queue('pending') limit 1), 'alice', 'queue carries the nickname');
select tests.eq((select id from public.admin_queue('reported') limit 1), tests.id('hid'), 'reported queue: oldest open report first');
select tests.eq((select open_reports from public.admin_queue('reported') where id = tests.id('pub')), 2, 'report count per post');
select tests.eq((select report_reasons from public.admin_queue('reported') where id = tests.id('pub')),
                array['personal info', 'spam'], 'distinct reasons');
select tests.eq((select author_hidden from public.admin_queue('reported') where id = tests.id('pub')), 1, 'author history: hidden posts');
select tests.eq((select author_approved from public.admin_queue('reported') where id = tests.id('pub')), 2, 'author history: approved posts');
select tests.throws_hint($$ select * from public.admin_queue('everything') $$, 'invalid_argument', 'unknown queue');
select tests.eq((select count(*)::int from public.admin_post_reports(tests.id('pub'))), 2, 'all reports of a post');
select tests.eq((select note from public.admin_post_reports(tests.id('pub')) limit 1), 'same sticker posted again', 'report notes are shown');

-- Approve
select tests.eq(public.admin_moderate(tests.id('old'), 'approve', 'op@example.com') ->> 'status', 'public', 'approve -> public');
reset role;
select tests.eq((select approved_count from private.profiles where id = '00000000-0000-0000-0000-00000000000a'), 1, 'approval counts for the author');
set role service_role; select tests.claims(null);
select tests.eq((public.admin_stats() ->> 'pending_count')::int, 1, 'approved post leaves the queue');

-- Reject
select tests.eq(public.admin_moderate(tests.id('new'), 'reject', 'op@example.com') ->> 'status', 'hidden', 'reject -> hidden');

-- Remove
select tests.eq(public.admin_remove_post(tests.id('pub'), 'op@example.com') ->> 'image_key',
                'posts/' || tests.id('pub') || '/full.heic', 'remove returns the image keys for the Worker');
select tests.eq((select status from public.posts where id = tests.id('pub')), 'removed', 'removed');
select tests.ok((select bool_and(resolution = 'removed') from public.reports where post_id = tests.id('pub')), 'its reports are closed');
select tests.eq((public.admin_stats() ->> 'reported_count')::int, 1, 'removed post leaves the reported count');
select tests.eq(public.admin_remove_post(tests.id('pub'), 'op@example.com') ->> 'status', 'removed', 'removing twice is fine');
select tests.throws_hint($$ select public.admin_remove_post(gen_random_uuid(), 'op') $$, 'not_found', 'unknown post');

-- Ban / unban
select tests.eq((public.admin_set_ban('00000000-0000-0000-0000-00000000000b', true, 'op@example.com', 'repeat spam') ->> 'banned')::boolean,
                true, 'ban');
reset role;
select tests.ok((select banned_at is not null from private.profiles where id = '00000000-0000-0000-0000-00000000000b'), 'banned_at set');
set role service_role; select tests.claims(null);
select tests.eq((select author_banned from public.admin_queue('reported') where id = tests.id('hid')), true, 'queue shows the ban');
reset role;
set role anon; select tests.claims(null);
select tests.eq((select count(*)::int from public.posts where author_id = '00000000-0000-0000-0000-00000000000b'), 0, 'banned author: nothing visible to others');
reset role;
set role service_role; select tests.claims(null);
select public.admin_set_ban('00000000-0000-0000-0000-00000000000b', false, 'op@example.com');
reset role;
select tests.ok((select banned_at is null from private.profiles where id = '00000000-0000-0000-0000-00000000000b'), 'unban clears banned_at');
set role service_role; select tests.claims(null);
select tests.throws_hint($$ select public.admin_set_ban(gen_random_uuid(), true, 'op') $$, 'not_found', 'unknown user');

-- Log
select tests.eq((select array_agg(action) from public.admin_log()),
                array['unban', 'ban', 'remove', 'remove', 'reject', 'approve'], 'every action logged, newest first');
select tests.eq((select actor from public.admin_log() limit 1), 'op@example.com', 'actor recorded');
select tests.eq((select note from public.admin_log() where action = 'ban'), 'repeat spam', 'ban note recorded');
select tests.eq((select user_id from public.admin_log() where action = 'approve'),
                '00000000-0000-0000-0000-00000000000a'::uuid, 'post actions record the author');
reset role;

rollback;
