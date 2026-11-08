-- Schema v2, part 1: a dedicated `mox` schema with a metadata row.
--
-- v2 lives in its own schema so Mox can be installed inside a Supabase
-- project that already runs another app (#40) without touching its tables.
-- Access is limited to one dedicated auth user, the owner, instead of the
-- anon role, because in a shared project the publishable key is often public.
--
-- Additive: v1's public.current_file keeps working until both apps move to
-- v2 (cleanup tracked in #49). Idempotent, safe to re-run.

create schema if not exists mox;

-- The anon role gets nothing in this schema. Signed-in users can see it, and
-- row level security decides what they can actually read or write.
revoke all on schema mox from anon;
grant usage on schema mox to authenticated, service_role;

------------------------------------------------------------
-- mox.meta: one row with the schema version and the owner
------------------------------------------------------------
create table if not exists mox.meta (
    id             int primary key default 1,
    schema_version int not null,
    -- The auth user allowed to use Mox. Set by the setup wizard or by hand
    -- (see backend/README.md). Until then nobody has access.
    owner_id       uuid references auth.users (id) on delete set null,
    constraint meta_singleton check (id = 1)
);

insert into mox.meta (id, schema_version) values (1, 2)
on conflict (id) do update
    set schema_version = greatest(mox.meta.schema_version, excluded.schema_version);

alter table mox.meta enable row level security;

grant select on mox.meta to authenticated;
grant all on mox.meta to service_role;

drop policy if exists "owner reads meta" on mox.meta;
create policy "owner reads meta" on mox.meta
    for select to authenticated
    using (owner_id = (select auth.uid()));

------------------------------------------------------------
-- mox.owner_id(): used by every policy
-- security definer so policies can read the owner even when the caller
-- can't see mox.meta. search_path is pinned so the function can't be hijacked.
------------------------------------------------------------
create or replace function mox.owner_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
    select owner_id from mox.meta where id = 1
$$;

revoke all on function mox.owner_id() from public, anon;
grant execute on function mox.owner_id() to authenticated, service_role;
