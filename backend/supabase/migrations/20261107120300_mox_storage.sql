-- Schema v2, part 3: storage rules for the one object, `current`.
--
--   * bucket cap lowered to 50 MB, the free plan's upload limit (#35)
--   * v1's anon policies are narrowed to v1's object names (`current.<ext>`)
--     so they can't reach v2's object. They go away entirely in #49
--   * v2's object `current` (fixed name, #34) is owner-only (#40)

update storage.buckets set file_size_limit = 52428800 where id = 'mox';

-- v1 compatibility: anon keeps access to `current.<ext>` only.
drop policy if exists "mox bucket read"   on storage.objects;
drop policy if exists "mox bucket write"  on storage.objects;
drop policy if exists "mox bucket update" on storage.objects;
drop policy if exists "mox bucket delete" on storage.objects;

create policy "mox bucket read" on storage.objects
    for select to anon
    using (bucket_id = 'mox' and name like 'current.%');
create policy "mox bucket write" on storage.objects
    for insert to anon
    with check (bucket_id = 'mox' and name like 'current.%');
create policy "mox bucket update" on storage.objects
    for update to anon
    using (bucket_id = 'mox' and name like 'current.%')
    with check (bucket_id = 'mox' and name like 'current.%');
create policy "mox bucket delete" on storage.objects
    for delete to anon
    using (bucket_id = 'mox' and name like 'current.%');

-- v2: the owner, and only the owner, can use `current`.
drop policy if exists "mox owner read"   on storage.objects;
drop policy if exists "mox owner write"  on storage.objects;
drop policy if exists "mox owner update" on storage.objects;
drop policy if exists "mox owner delete" on storage.objects;

create policy "mox owner read" on storage.objects
    for select to authenticated
    using (bucket_id = 'mox' and name = 'current' and (select auth.uid()) = mox.owner_id());
create policy "mox owner write" on storage.objects
    for insert to authenticated
    with check (bucket_id = 'mox' and name = 'current' and (select auth.uid()) = mox.owner_id());
create policy "mox owner update" on storage.objects
    for update to authenticated
    using (bucket_id = 'mox' and name = 'current' and (select auth.uid()) = mox.owner_id())
    with check (bucket_id = 'mox' and name = 'current' and (select auth.uid()) = mox.owner_id());
create policy "mox owner delete" on storage.objects
    for delete to authenticated
    using (bucket_id = 'mox' and name = 'current' and (select auth.uid()) = mox.owner_id());
