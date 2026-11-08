-- Schema v2, part 2: mox.current_file, the one slot.
--
-- Changes from v1's public.current_file:
--   * uploaded_from ('mac','android') becomes source_platform (four
--     platforms) + source_device_id, so a client skips its own uploads, not
--     every upload from its platform
--   * kind + item_count for multi-file bundles (DESIGN.md §9)
--   * size limited to 50 MB, the Supabase free plan's upload limit (#35)
--   * no storage_path: the object is always named `current` (#34)
--   * uploaded_at is refreshed on every replace (#48)
-- Only the owner (mox.owner_id()) can read or write it.

create table if not exists mox.current_file (
    id               int primary key default 1,
    original_name    text not null,
    mime_type        text,
    size_bytes       bigint not null,
    kind             text not null default 'file',
    item_count       int not null default 1,
    source_platform  text not null,
    source_device_id uuid not null,
    uploaded_at      timestamptz not null default now(),

    constraint current_file_singleton check (id = 1),
    constraint current_file_name_length check (char_length(original_name) between 1 and 255),
    constraint current_file_size check (size_bytes between 1 and 52428800),
    constraint current_file_kind check (kind in ('file', 'bundle')),
    constraint current_file_item_count check (
        (kind = 'file' and item_count = 1) or (kind = 'bundle' and item_count >= 2)
    ),
    constraint current_file_platform check (
        source_platform in ('macos', 'windows', 'android', 'ios')
    )
);

alter table mox.current_file enable row level security;

grant select, insert, update, delete on mox.current_file to authenticated;
grant all on mox.current_file to service_role;

drop policy if exists "owner reads current file"   on mox.current_file;
drop policy if exists "owner inserts current file" on mox.current_file;
drop policy if exists "owner updates current file" on mox.current_file;
drop policy if exists "owner deletes current file" on mox.current_file;

create policy "owner reads current file" on mox.current_file
    for select to authenticated
    using ((select auth.uid()) = mox.owner_id());

create policy "owner inserts current file" on mox.current_file
    for insert to authenticated
    with check ((select auth.uid()) = mox.owner_id());

create policy "owner updates current file" on mox.current_file
    for update to authenticated
    using ((select auth.uid()) = mox.owner_id())
    with check ((select auth.uid()) = mox.owner_id());

create policy "owner deletes current file" on mox.current_file
    for delete to authenticated
    using ((select auth.uid()) = mox.owner_id());
