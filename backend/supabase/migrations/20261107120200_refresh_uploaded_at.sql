-- Refresh uploaded_at every time the row is replaced (#48).
--
-- Clients replace the row with a PostgREST upsert that doesn't send
-- uploaded_at. PostgREST only updates the columns in the payload, so without
-- this trigger uploaded_at kept the time of the very first upload, and
-- Android (which dedupes on storage_path|uploaded_at) missed later files.
-- Applied to v1's table too, so existing installs get the fix.

create or replace function public.mox_touch_uploaded_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.uploaded_at := now();
    return new;
end;
$$;

drop trigger if exists touch_uploaded_at on public.current_file;
create trigger touch_uploaded_at
    before update on public.current_file
    for each row execute function public.mox_touch_uploaded_at();

drop trigger if exists touch_uploaded_at on mox.current_file;
create trigger touch_uploaded_at
    before update on mox.current_file
    for each row execute function public.mox_touch_uploaded_at();
