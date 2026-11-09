-- Publishes mox.current_file to Supabase Realtime, so a device can hear that
-- the slot changed without polling (#37, DESIGN.md §3.1). Realtime applies
-- the table's row level security, so only the owner receives events.
do $$
begin
    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime' and schemaname = 'mox' and tablename = 'current_file'
    ) then
        alter publication supabase_realtime add table mox.current_file;
    end if;
end
$$;
