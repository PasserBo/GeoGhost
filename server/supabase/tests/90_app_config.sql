-- app_config: version gate, publishing / signup pauses, admin_set_app_config
begin;

select tests.make_profile('00000000-0000-0000-0000-00000000000a', 'alice');
select tests.make_profile('00000000-0000-0000-0000-00000000000b', 'bob');
insert into tests.ids values ('p', tests.make_post('00000000-0000-0000-0000-00000000000b', 'public'));

-- Version comparison
select tests.ok(private.version_lt('1.0.9', '1.1.0'), '1.0.9 < 1.1.0');
select tests.ok(private.version_lt('1.9.0', '1.10.0'), 'numeric, not text: 1.9.0 < 1.10.0');
select tests.ok(not private.version_lt('1.1', '1.1.0'), '1.1 equals 1.1.0');
select tests.ok(not private.version_lt('2.0.0', '1.99.99'), '2.0.0 is not below 1.99.99');
select tests.ok(private.version_lt('garbage', '0.0.1'), 'garbage counts as 0.0.0');

-- Everyone can read the config; nobody but the service role can write it.
set role anon; select tests.claims(null);
select tests.eq((select min_online_version from public.app_config), '1.1.0', 'anon reads app_config');
select tests.throws_state($$ update public.app_config set publishing_enabled = false $$, '42501', 'anon cannot update app_config');
reset role;
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000a');
select tests.throws_state($$ update public.app_config set publishing_enabled = false $$, '42501', 'authenticated cannot update app_config');
select tests.throws_state($$ select public.admin_set_app_config('1.1.0', '1.1.0', false, true, null, 'me') $$, '42501',
                          'authenticated cannot call admin_set_app_config');
select tests.throws_state($$ select private.create_post(gen_random_uuid(), 'sticker', 35.0, 139.0) $$, '42501',
                          'the unchecked create_post is not callable');

-- Too old / missing header: every client write refused with update_required.
select tests.version('1.0.0');
select tests.throws_hint($$ select public.create_post(gen_random_uuid(), 'sticker', 35.0, 139.0) $$, 'update_required', 'old app cannot publish');
select tests.throws_hint($$ select public.upsert_profile('Alice', 1) $$, 'update_required', 'old app cannot change nickname');
select tests.throws_hint($$ select public.report_post(tests.id('p'), 'spam') $$, 'update_required', 'old app cannot report');
select tests.throws_hint($$ insert into public.likes (post_id) values (tests.id('p')) $$, 'update_required', 'old app cannot like');
select tests.throws_hint($$ insert into public.saves (post_id) values (tests.id('p')) $$, 'update_required', 'old app cannot save');
select tests.throws_hint($$ insert into public.blocks (blocked_id) values ('00000000-0000-0000-0000-00000000000b') $$, 'update_required', 'old app cannot block');
select tests.ok((select count(*) = 1 from public.posts where id = tests.id('p')), 'old app can still read public posts');
select tests.version(null);
select tests.throws_hint($$ select public.create_post(gen_random_uuid(), 'sticker', 35.0, 139.0) $$, 'update_required', 'missing header counts as too old');
select tests.version('1.1.0');
insert into public.likes (post_id) values (tests.id('p'));
select tests.ok(true, 'current app can like');
select tests.version('1.2.0');
select tests.ok((public.create_post(gen_random_uuid(), 'sticker', 35.0, 139.0, width => 1024, height => 768)) is not null, 'newer app can publish');
reset role;

-- Publishing paused: publishing_paused, even when the quota would also refuse.
set role service_role; select tests.claims(null);
select tests.eq((public.admin_set_app_config('1.1.0', '1.2.0', false, true, null, 'op@example.com')).publishing_enabled, false,
                'operator pauses publishing');
reset role;
update public.quota_config set value = 0 where key = 'posts_per_month';
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000a'); select tests.version('1.1.0');
select tests.throws_hint($$ select public.create_post(gen_random_uuid(), 'sticker', 35.0, 139.0) $$, 'publishing_paused',
                         'paused publishing says paused, not quota');
select tests.throws_hint($$ select public.create_post(gen_random_uuid(), 'sticker', 35.0, 139.0) $$, 'publishing_paused',
                         'paused publishing refused again');
select tests.version('1.0.0');
select tests.throws_hint($$ select public.create_post(gen_random_uuid(), 'sticker', 35.0, 139.0) $$, 'update_required',
                         'an outdated app hears update_required first');
select tests.version('1.1.0');
reset role;

-- Signups paused: only a first profile is refused.
set role service_role; select tests.claims(null);
select public.admin_set_app_config('1.1.0', '1.1.0', true, false, null, 'op@example.com');
reset role;
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000c');
select tests.throws_hint($$ select public.upsert_profile('Carol', 1) $$, 'signups_paused', 'new member refused while signups are paused');
select tests.claims('00000000-0000-0000-0000-00000000000a');
select tests.eq((public.upsert_profile('Alice2', 1)).nickname, 'Alice2', 'existing member can still change nickname');
reset role;

-- admin_set_app_config validation and log
set role service_role; select tests.claims(null);
select tests.throws_hint($$ select public.admin_set_app_config('1.1', '1.1.0', true, true, null, 'op') $$, 'invalid_argument', 'version must be x.y.z');
select tests.throws_hint($$ select public.admin_set_app_config('1.2.0', '1.1.0', true, true, null, 'op') $$, 'invalid_argument', 'latest below minimum refused');
select tests.throws_hint($$ select public.admin_set_app_config('1.1.0', '1.1.0', true, true, '{"fr":"x"}', 'op') $$, 'invalid_argument', 'unknown notice language refused');
select tests.throws_hint($$ select public.admin_set_app_config('1.1.0', '1.1.0', true, true, '["x"]', 'op') $$, 'invalid_argument', 'notice must be an object');
select tests.throws_hint($$ select public.admin_set_app_config('1.1.0', '1.1.0', true, true, jsonb_build_object('en', repeat('x', 281)), 'op') $$, 'invalid_argument', 'notice text too long');
select tests.eq((public.admin_set_app_config('1.1.0', '1.1.0', true, true, '{"en":"Maintenance tonight","ja":"  "}', 'op')).notice,
                '{"en":"Maintenance tonight"}'::jsonb, 'blank notice languages are dropped');
select tests.eq((public.admin_set_app_config('1.1.0', '1.1.0', true, true, '{"en":" "}', 'op')).notice, null::jsonb,
                'an all-blank notice becomes no notice');
select tests.eq((select count(*) from public.admin_log() where action = 'config')::int, 4, 'each saved change is logged as config');
select tests.ok(exists (select 1 from public.admin_log() l
                  where l.action = 'config' and l.actor = 'op@example.com'
                    and l.note = 'min 1.1.0, latest 1.2.0, publishing paused, signups on, notice none'),
                'log note summarises the settings');
reset role;

-- Account deletion is never gated (it is a delete, not an insert).
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000a'); select tests.version('0.1.0');
delete from public.likes where user_id = auth.uid();
select tests.eq((select count(*) from public.likes where user_id = auth.uid())::int, 0, 'old app can still delete its likes');
reset role;

rollback;
