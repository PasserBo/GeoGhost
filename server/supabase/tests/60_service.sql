-- service-role-only functions: complete_post_upload, moderate_post; removal by the Worker
begin;

select tests.make_profile('00000000-0000-0000-0000-00000000000a', 'alice');
select tests.make_profile('00000000-0000-0000-0000-00000000000b', 'bob', approved => 3);
select tests.make_profile('00000000-0000-0000-0000-00000000000c', 'carol');
insert into tests.ids values
  ('a1', tests.make_post('00000000-0000-0000-0000-00000000000a', 'uploading')),
  ('a2', tests.make_post('00000000-0000-0000-0000-00000000000a', 'uploading')),
  ('a3', tests.make_post('00000000-0000-0000-0000-00000000000a', 'uploading')),
  ('a4', tests.make_post('00000000-0000-0000-0000-00000000000a', 'uploading')),
  ('b1', tests.make_post('00000000-0000-0000-0000-00000000000b', 'uploading')),
  ('c1', tests.make_post('00000000-0000-0000-0000-00000000000c', 'uploading')),
  ('c2', tests.make_post('00000000-0000-0000-0000-00000000000c', 'removed'));

-- not callable by clients
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000a');
select tests.throws_state($$ select public.complete_post_upload(tests.id('a1')) $$, '42501', 'authenticated cannot call complete_post_upload');
select tests.throws_state($$ select public.moderate_post(tests.id('a1'), 'approve') $$, '42501', 'authenticated cannot call moderate_post');
reset role;
set role anon; select tests.claims(null);
select tests.throws_state($$ select public.complete_post_upload(tests.id('a1')) $$, '42501', 'anon cannot call complete_post_upload');
select tests.throws_state($$ select public.moderate_post(tests.id('a1'), 'approve') $$, '42501', 'anon cannot call moderate_post');
reset role;

set role service_role; select tests.claims(null);
select tests.eq(public.complete_post_upload(tests.id('a1')) ->> 'status', 'pending', 'new author: uploading -> pending');
select tests.eq(public.complete_post_upload(tests.id('a1')) ->> 'status', 'pending', 'complete_post_upload is idempotent');
select tests.eq(public.complete_post_upload(tests.id('b1')) ->> 'status', 'public', 'trusted author: complete returns public');
select tests.ok((select status = 'public' and published_at is not null from public.posts where id = tests.id('b1')),
                'trusted author (approved_count >= 3): uploading -> public with published_at');
select tests.throws_hint($$ select public.complete_post_upload(tests.id('c2')) $$, 'invalid_status', 'removed post cannot be completed');
select tests.throws_hint($$ select public.complete_post_upload(gen_random_uuid()) $$, 'not_found', 'unknown post');
select tests.throws_hint($$ select public.moderate_post(tests.id('a1'), 'maybe') $$, 'invalid_argument', 'unknown decision');
select tests.throws_hint($$ select public.moderate_post(tests.id('a2'), 'approve') $$, 'invalid_status', 'cannot moderate an uploading post');
reset role;

set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000a');
select tests.eq((select status from public.posts where id = tests.id('a1')), 'pending', 'author sees own pending post');
select tests.claims('00000000-0000-0000-0000-00000000000c');
select tests.eq((select count(*) from public.posts where id = tests.id('a1'))::int, 0, 'others do not see a pending post');
reset role;

-- three approvals make alice trusted
set role service_role; select tests.claims(null);
select tests.eq(public.moderate_post(tests.id('a1'), 'approve') ->> 'status', 'public', 'approve: pending -> public');
select tests.eq(public.moderate_post(tests.id('a1'), 'approve') ->> 'status', 'public', 'approving a public post is a no-op');
select public.complete_post_upload(tests.id('a2')), public.moderate_post(tests.id('a2'), 'approve');
select tests.eq(public.complete_post_upload(tests.id('a3')) ->> 'status', 'pending', 'two approvals: still reviewed');
select public.moderate_post(tests.id('a3'), 'reject');
reset role;
select tests.eq((select approved_count from private.profiles where id = '00000000-0000-0000-0000-00000000000a'), 2,
                'approved_count counts approvals only (no-op and reject excluded)');
select tests.ok((select published_at is not null from public.posts where id = tests.id('a1')), 'approval sets published_at');

set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000a');
select tests.eq((select status from public.posts where id = tests.id('a3')), 'hidden', 'rejected post is hidden; author still sees it');
select tests.claims('00000000-0000-0000-0000-00000000000c');
select tests.eq((select count(*) from public.posts where id = tests.id('a3'))::int, 0, 'rejected post invisible to others');
reset role;

set role service_role; select tests.claims(null);
select public.moderate_post(tests.id('a3'), 'approve');
select tests.eq(public.complete_post_upload(tests.id('a4')) ->> 'status', 'public', 'after 3 approvals new posts go public directly');
select tests.eq((select count(*) from public.posts)::int, 7, 'service_role reads every post (bypasses RLS)');

-- Worker's DELETE /v1/posts/{id}: PATCH status = removed
reset role;
update private.profiles set avatar_post_id = tests.id('a4') where id = '00000000-0000-0000-0000-00000000000a';
set role service_role; select tests.claims(null);
update public.posts set status = 'removed' where id = tests.id('a4');
reset role;
select tests.ok((select removed_at is not null from public.posts where id = tests.id('a4')), 'removal stamps removed_at');
select tests.ok((select avatar_post_id is null from private.profiles where id = '00000000-0000-0000-0000-00000000000a'),
                'removal clears the avatar reference');
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000a');
select tests.eq((select count(*) from public.posts where id = tests.id('a4'))::int, 0, 'removed post invisible to its author');
reset role;

-- banned author cannot complete an upload
update private.profiles set banned_at = now() where id = '00000000-0000-0000-0000-00000000000c';
set role service_role; select tests.claims(null);
select tests.throws_hint($$ select public.complete_post_upload(tests.id('c1')) $$, 'banned', 'banned author''s upload refused');
reset role;

rollback;
