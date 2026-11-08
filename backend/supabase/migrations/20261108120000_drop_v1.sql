-- Drop schema v1 now that both apps speak v2 (#49).
--
-- After this, the project's publishable key on its own can't read or write
-- any Mox data: the table and the storage object are owner-only (#40).
-- Idempotent, safe to re-run.

-- 1. The uploaded_at trigger function (#48) moves into the mox schema, so
--    Mox leaves nothing behind in `public`.
create or replace function mox.touch_uploaded_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.uploaded_at := now();
    return new;
end;
$$;

drop trigger if exists touch_uploaded_at on mox.current_file;
create trigger touch_uploaded_at
    before update on mox.current_file
    for each row execute function mox.touch_uploaded_at();

-- 2. The v1 table. Its four anon policies and its trigger go with it.
drop table if exists public.current_file;
drop function if exists public.mox_touch_uploaded_at();

-- 3. v1's anonymous storage policies (`current.<ext>` objects).
drop policy if exists "mox bucket read"   on storage.objects;
drop policy if exists "mox bucket write"  on storage.objects;
drop policy if exists "mox bucket update" on storage.objects;
drop policy if exists "mox bucket delete" on storage.objects;

-- Leftover v1 objects (`current.<ext>`) can't be deleted from SQL: Supabase
-- only allows that through the Storage API. Nobody can reach them anymore;
-- remove them from the dashboard (Storage → mox) to free the space (#34).
