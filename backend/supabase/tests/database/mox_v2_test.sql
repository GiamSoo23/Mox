-- Tests for schema v2: the `mox` schema, its constraints, and who can read
-- and write what (#7, #40, #48, #49). Rolled back at the end.
-- Run with: cd backend && npx supabase test db
begin;
create extension if not exists pgtap with schema extensions;

select plan(30);

-- Two users: the Mox owner, and a stranger (e.g. a user of another app
-- living in the same Supabase project).
insert into auth.users (id, aud, role, email)
values ('11111111-1111-1111-1111-111111111111', 'authenticated', 'authenticated', 'owner@mox.test'),
       ('22222222-2222-2222-2222-222222222222', 'authenticated', 'authenticated', 'stranger@mox.test');
update mox.meta set owner_id = '11111111-1111-1111-1111-111111111111' where id = 1;


-- Shape -------------------------------------------------------------------
select has_schema('mox', 'schema mox exists');
select has_table('mox', 'meta', 'mox.meta exists');
select has_table('mox', 'current_file', 'mox.current_file exists');
select is((select schema_version from mox.meta), 2, 'schema_version is 2');
select is(
    (select file_size_limit from storage.buckets where id = 'mox'),
    52428800::bigint,
    'bucket cap is 50 MB, the free plan limit (#35)'
);
select policies_are(
    'mox', 'current_file',
    array['owner reads current file', 'owner inserts current file',
          'owner updates current file', 'owner deletes current file'],
    'mox.current_file has exactly the four owner policies'
);

select ok(
    exists (select 1 from pg_publication_tables
            where pubname = 'supabase_realtime' and schemaname = 'mox' and tablename = 'current_file'),
    'mox.current_file is published to Realtime (#37)'
);

-- Constraints (checked as the table owner, so RLS doesn't interfere) --------
select throws_ok(
    $$ insert into mox.current_file (id, original_name, size_bytes, source_platform, source_device_id)
       values (2, 'IMG_0001.jpg', 2048, 'macos', '33333333-3333-3333-3333-333333333333'::uuid) $$,
    '23514', null, 'a second row (id = 2) is rejected'
);
select throws_ok(
    $$ insert into mox.current_file (original_name, size_bytes, source_platform, source_device_id)
       values ('IMG_0001.jpg', 2048, 'mac', '33333333-3333-3333-3333-333333333333'::uuid) $$,
    '23514', null, 'v1 platform name "mac" is rejected (v2 uses "macos")'
);
select throws_ok(
    $$ insert into mox.current_file (original_name, size_bytes, source_platform, source_device_id)
       values ('IMG_0001.jpg', 52428801, 'macos', '33333333-3333-3333-3333-333333333333'::uuid) $$,
    '23514', null, 'files over 50 MB are rejected'
);
select throws_ok(
    $$ insert into mox.current_file (original_name, size_bytes, source_platform, source_device_id)
       values ('IMG_0001.jpg', 0, 'macos', '33333333-3333-3333-3333-333333333333'::uuid) $$,
    '23514', null, 'empty files are rejected'
);
select throws_ok(
    $$ insert into mox.current_file (original_name, size_bytes, kind, item_count, source_platform, source_device_id)
       values ('IMG_0001.jpg', 2048, 'bundle', 1, 'macos', '33333333-3333-3333-3333-333333333333'::uuid) $$,
    '23514', null, 'a bundle with a single item is rejected'
);
select throws_ok(
    $$ insert into mox.current_file (original_name, size_bytes, kind, item_count, source_platform, source_device_id)
       values ('IMG_0001.jpg', 2048, 'file', 3, 'macos', '33333333-3333-3333-3333-333333333333'::uuid) $$,
    '23514', null, 'a plain file with item_count 3 is rejected'
);
select throws_ok(
    $$ insert into mox.current_file (original_name, size_bytes, source_platform)
       values ('IMG_0001.jpg', 2048, 'macos') $$,
    '23502', null, 'source_device_id is required'
);

-- anon: no access at all (#40) -------------------------------------------
set local role anon;
select throws_ok(
    $$ select * from mox.current_file $$,
    '42501', null, 'anon cannot read mox.current_file'
);
select throws_ok(
    $$ select mox.owner_id() $$,
    '42501', null, 'anon cannot call mox.owner_id()'
);
reset role;

-- A signed-in stranger: sees nothing, writes nothing ----------------------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
select throws_ok(
    $$ insert into mox.current_file (original_name, size_bytes, source_platform, source_device_id)
       values ('IMG_0001.jpg', 2048, 'macos', '33333333-3333-3333-3333-333333333333'::uuid) $$,
    '42501', null, 'a stranger cannot insert the row'
);
select is_empty($$ select * from mox.meta $$, 'a stranger cannot read mox.meta');
reset role;

-- The owner: full use of the slot -----------------------------------------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
select lives_ok(
    $$ insert into mox.current_file (original_name, mime_type, size_bytes, source_platform, source_device_id, uploaded_at)
       values ('IMG_0001.jpg', 'image/jpeg', 2048, 'macos', '33333333-3333-3333-3333-333333333333'::uuid, '2000-01-01T00:00:00Z') $$,
    'the owner can insert the row'
);
select results_eq($$ select count(*)::int from mox.current_file $$, array[1], 'the owner can read the row');
select results_eq($$ select schema_version from mox.meta $$, array[2], 'the owner can read the schema version');

-- #48: the same statement PostgREST generates for an upsert that doesn't
-- send uploaded_at. The trigger must still refresh it.
select lives_ok(
    $$ insert into mox.current_file (id, original_name, size_bytes, source_platform, source_device_id)
       values (1, 'second.png', 4096, 'android', '44444444-4444-4444-4444-444444444444')
       on conflict (id) do update set
           original_name = excluded.original_name,
           size_bytes = excluded.size_bytes,
           source_platform = excluded.source_platform,
           source_device_id = excluded.source_device_id $$,
    'the owner can replace the row with a PostgREST-style upsert'
);
select ok(
    (select uploaded_at > '2000-01-01T00:00:00Z' from mox.current_file),
    'replacing the row refreshes uploaded_at (#48)'
);

-- Storage: only the owner can use the object `current` --------------------
select lives_ok(
    $$ insert into storage.objects (bucket_id, name) values ('mox', 'current') $$,
    'the owner can create the storage object "current"'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
select is_empty(
    $$ select 1 from storage.objects where bucket_id = 'mox' and name = 'current' $$,
    'a stranger cannot see the storage object "current"'
);
reset role;

set local role anon;
select throws_ok(
    $$ insert into storage.objects (bucket_id, name) values ('mox', 'current') $$,
    '42501', null, 'anon cannot write the v2 object "current"'
);
select throws_ok(
    $$ insert into storage.objects (bucket_id, name) values ('mox', 'current.jpg') $$,
    '42501', null, 'anon cannot write v1-style objects either: the v1 policies are gone (#49)'
);
reset role;

-- v1 is gone (#49): nothing of Mox is left in public, and no policy gives
-- the anon role access to the bucket.
select hasnt_table('public', 'current_file', 'the v1 table public.current_file is gone');
select hasnt_function('public', 'mox_touch_uploaded_at', 'the v1 trigger function is gone from public');
select is_empty(
    $$ select 1 from pg_policies
       where schemaname = 'storage' and tablename = 'objects' and policyname like 'mox bucket %' $$,
    'the v1 anon storage policies are gone'
);

select * from finish();
rollback;
