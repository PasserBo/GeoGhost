-- upsert_profile + profiles view (column visibility, not writable)
begin;

set role anon; select tests.claims(null);
select tests.throws_state($$ select public.upsert_profile('x', 1) $$, '42501', 'anon cannot call upsert_profile');
reset role;

set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000a');
select tests.throws_hint($$ select public.upsert_profile('   ', 1) $$, 'invalid_argument', 'blank nickname rejected');
select tests.throws_hint($$ select public.upsert_profile(repeat('x', 25), 1) $$, 'invalid_argument', '25-character nickname rejected');
select tests.throws_hint($$ select public.upsert_profile('Alice', 2) $$, 'invalid_argument', 'unknown (future) terms_version rejected');

select tests.eq((public.upsert_profile('  Alice  ', 1)).nickname, 'Alice', 'first call creates the profile (nickname trimmed)');
select tests.ok((select terms_version = 1 and terms_accepted_at is not null and approved_count = 0
                        and nickname_changed_at is null and banned_at is null and created_at is not null
                 from public.profiles where id = '00000000-0000-0000-0000-00000000000a'),
                'owner reads own private columns');

select tests.eq((public.upsert_profile('Alice2', 1)).nickname, 'Alice2', 'first nickname change allowed');
select tests.throws_hint($$ select public.upsert_profile('Alice3', 1) $$, 'nickname_cooldown', 'second change within 7 days refused');
select tests.eq((public.upsert_profile('Alice2', 1)).nickname, 'Alice2', 'same nickname again is not a change');

select tests.claims('00000000-0000-0000-0000-00000000000b');
select tests.eq((public.upsert_profile(repeat('字', 24), 1)).nickname, repeat('字', 24), '24-character CJK nickname accepted');
select tests.ok((select nickname = 'Alice2' and terms_version is null and terms_accepted_at is null
                        and approved_count is null and banned_at is null and created_at is null
                        and nickname_changed_at is null
                 from public.profiles where id = '00000000-0000-0000-0000-00000000000a'),
                'other users see only id / nickname / avatar_post_id');
select tests.eq((select count(*) from public.profiles where banned_at is not null or approved_count is not null)::int, 1,
                'filtering on private columns cannot reveal other users');
select tests.throws_state($$ update public.profiles set nickname = 'pwned' where id = '00000000-0000-0000-0000-00000000000a' $$,
                          '42501', 'profiles view is not updatable by clients');
select tests.throws_state($$ insert into public.profiles (id, nickname) values ('00000000-0000-0000-0000-00000000000c', 'x') $$,
                          '42501', 'profiles view is not insertable by clients');
select tests.throws_state($$ select * from private.profiles $$, '42501', 'private.profiles not readable by clients');
select tests.throws_state($$ select * from public.quota_config $$, '42501', 'quota_config not readable by clients');
reset role;

set role anon; select tests.claims(null);
select tests.eq((select count(*) from public.profiles)::int, 2, 'anon reads profiles');
select tests.ok((select terms_version is null and banned_at is null from public.profiles
                 where id = '00000000-0000-0000-0000-00000000000a'), 'anon sees no private columns');
reset role;

-- cooldown expires after nickname_change_days
update private.profiles set nickname_changed_at = now() - interval '8 days'
 where id = '00000000-0000-0000-0000-00000000000a';
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000a');
select tests.eq((public.upsert_profile('Alice3', 1)).nickname, 'Alice3', 'nickname change allowed after 7 days');
reset role;

-- terms update
update public.quota_config set value = 2 where key = 'terms_version';
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000a');
select tests.eq((public.upsert_profile('Alice3', 2)).terms_version, 2, 'accepting new terms records the version');
select tests.eq((public.upsert_profile('Alice3', 1)).terms_version, 2, 'accepted terms version is never downgraded');
reset role;

-- banned
update private.profiles set banned_at = now() where id = '00000000-0000-0000-0000-00000000000a';
set role authenticated; select tests.claims('00000000-0000-0000-0000-00000000000a');
select tests.throws_hint($$ select public.upsert_profile('Alice4', 2) $$, 'banned', 'banned user cannot update profile');
reset role;

rollback;
