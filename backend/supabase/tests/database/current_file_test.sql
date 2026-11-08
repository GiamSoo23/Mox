-- Tests for the v1 schema (migration 20260526000000_initial_schema).
-- Run with: cd backend && npx supabase test db
-- Everything runs inside a transaction that is rolled back at the end.
begin;
create extension if not exists pgtap with schema extensions;

select plan(11);

-- Table shape -----------------------------------------------------------
select has_table('public', 'current_file', 'current_file table exists');
select col_is_pk('public', 'current_file', 'id', 'id is the primary key');

-- The singleton: only id = 1 can exist ----------------------------------
select throws_ok(
    $$ insert into public.current_file (id, storage_path, original_name, size_bytes, uploaded_from)
       values (2, 'current.txt', 'a.txt', 1, 'mac') $$,
    '23514', null,
    'a second row (id = 2) is rejected by the singleton check'
);

select throws_ok(
    $$ insert into public.current_file (storage_path, original_name, size_bytes, uploaded_from)
       values ('current.txt', 'a.txt', 1, 'windows') $$,
    '23514', null,
    'uploaded_from only accepts mac or android'
);

select lives_ok(
    $$ insert into public.current_file (storage_path, original_name, size_bytes, uploaded_from)
       values ('current.jpg', 'IMG_0001.jpg', 2048, 'android') $$,
    'the singleton row can be inserted with id defaulting to 1'
);

select ok(
    (select uploaded_at is not null from public.current_file where id = 1),
    'uploaded_at defaults to now()'
);

-- Storage bucket --------------------------------------------------------
select is(
    (select public from storage.buckets where id = 'mox'),
    false,
    'bucket mox exists and is private'
);

select is(
    (select file_size_limit from storage.buckets where id = 'mox'),
    524288000::bigint,
    'bucket cap is 500 MB in v1 (free plan enforces 50 MB, see #35)'
);

-- Row level security ----------------------------------------------------
select ok(
    (select relrowsecurity from pg_class where oid = 'public.current_file'::regclass),
    'RLS is enabled on current_file'
);

select policies_are(
    'public', 'current_file',
    array['mox anon read', 'mox anon write', 'mox anon update', 'mox anon delete'],
    'current_file has exactly the four v1 anon policies'
);

set local role anon;
select results_eq(
    $$ select count(*)::int from public.current_file $$,
    array[1],
    'the anon role can read the row (v1 policy)'
);
reset role;

select * from finish();
rollback;
