-- Mox schema. Paste into Supabase SQL editor and Run.
-- Idempotent — safe to re-run.

------------------------------------------------------------
-- Storage bucket
------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('mox', 'mox', false, 524288000)  -- 500 MB
on conflict (id) do update set file_size_limit = excluded.file_size_limit;

------------------------------------------------------------
-- Singleton table: the one current file
------------------------------------------------------------
create table if not exists public.current_file (
    id            int primary key default 1,
    storage_path  text not null,
    original_name text not null,
    mime_type     text,
    size_bytes    bigint not null,
    uploaded_from text not null check (uploaded_from in ('mac', 'android')),
    uploaded_at   timestamptz not null default now(),
    constraint singleton check (id = 1)
);

------------------------------------------------------------
-- Row Level Security
-- Mox is a personal app: the anon key (held only by you) gets full access.
-- The bucket itself is private; clients must sign URLs to read.
------------------------------------------------------------
alter table public.current_file enable row level security;

drop policy if exists "mox anon read"   on public.current_file;
drop policy if exists "mox anon write"  on public.current_file;
drop policy if exists "mox anon update" on public.current_file;
drop policy if exists "mox anon delete" on public.current_file;

create policy "mox anon read"   on public.current_file for select to anon using (true);
create policy "mox anon write"  on public.current_file for insert to anon with check (true);
create policy "mox anon update" on public.current_file for update to anon using (true) with check (true);
create policy "mox anon delete" on public.current_file for delete to anon using (true);

------------------------------------------------------------
-- Storage policies — same idea, bucket-scoped
------------------------------------------------------------
drop policy if exists "mox bucket read"   on storage.objects;
drop policy if exists "mox bucket write"  on storage.objects;
drop policy if exists "mox bucket update" on storage.objects;
drop policy if exists "mox bucket delete" on storage.objects;

create policy "mox bucket read"   on storage.objects for select to anon using (bucket_id = 'mox');
create policy "mox bucket write"  on storage.objects for insert to anon with check (bucket_id = 'mox');
create policy "mox bucket update" on storage.objects for update to anon using (bucket_id = 'mox') with check (bucket_id = 'mox');
create policy "mox bucket delete" on storage.objects for delete to anon using (bucket_id = 'mox');
