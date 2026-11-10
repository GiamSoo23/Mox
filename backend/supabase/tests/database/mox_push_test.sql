-- Tests for Web Push (#54): who can see subscriptions and the function's
-- secret, and that the trigger never blocks a send. Rolled back at the end.
begin;
create extension if not exists pgtap with schema extensions;

select plan(9);

insert into auth.users (id, aud, role, email)
values ('11111111-1111-1111-1111-111111111111', 'authenticated', 'authenticated', 'owner@mox.test'),
       ('22222222-2222-2222-2222-222222222222', 'authenticated', 'authenticated', 'stranger@mox.test');
update mox.meta set owner_id = '11111111-1111-1111-1111-111111111111' where id = 1;

select has_table('mox', 'push_subscriptions', 'mox.push_subscriptions exists');
select has_column('mox', 'meta', 'vapid_public_key', 'mox.meta has the VAPID public key');

-- Without a configuration, sending works and nothing is queued.
select lives_ok(
    $$ insert into mox.current_file (original_name, size_bytes, source_platform, source_device_id)
       values ('a.txt', 1, 'macos', '33333333-3333-3333-3333-333333333333'::uuid)
       on conflict (id) do update set original_name = excluded.original_name $$,
    'sending works while push is not set up'
);

-- The owner registers a phone; a stranger sees nothing.
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select lives_ok(
    $$ insert into mox.push_subscriptions (endpoint, p256dh, auth, device_id)
       values ('https://web.push.apple.com/test', 'key', 'secret', '44444444-4444-4444-4444-444444444444'::uuid) $$,
    'the owner can register a phone'
);
select throws_ok(
    $$ select * from mox.push_config $$,
    '42501', null, 'the owner can''t read the function secret through the API'
);
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is_empty($$ select 1 from mox.push_subscriptions $$, 'a stranger sees no subscriptions');
reset role;

-- With a configuration, a send from another device queues one request;
-- a send from the subscribed phone itself queues none.
insert into mox.push_config (function_url, secret) values ('http://127.0.0.1:9/functions/v1/mox-push', 's');
select lives_ok(
    $$ update mox.current_file set original_name = 'b.txt', source_device_id = '33333333-3333-3333-3333-333333333333' $$,
    'sending works with push set up, even if the function is unreachable'
);
select is(
    (select count(*)::int from net.http_request_queue where url like '%mox-push'), 1,
    'a send from another device asks the function to notify the phone'
);
update mox.current_file set original_name = 'c.txt', source_device_id = '44444444-4444-4444-4444-444444444444';
select is(
    (select count(*)::int from net.http_request_queue where url like '%mox-push'), 1,
    'a send from the phone itself notifies nobody'
);

select * from finish();
rollback;
