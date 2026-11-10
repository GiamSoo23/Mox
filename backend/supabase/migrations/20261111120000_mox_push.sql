-- Web Push for iPhone (#54, DESIGN.md §4.1). A phone that can't stay
-- connected registers a push subscription; when the slot changes, the
-- database hands the other devices' subscriptions to the mox-push Edge
-- Function in this same project, which sends the notifications. No third
-- party is involved. Idempotent, and inactive until setup fills
-- mox.push_config.

create extension if not exists pg_net with schema extensions;

-- The VAPID public key a device needs to subscribe. Readable by the owner.
alter table mox.meta add column if not exists vapid_public_key text;

------------------------------------------------------------
-- mox.push_subscriptions: one row per subscribed device
------------------------------------------------------------
create table if not exists mox.push_subscriptions (
    endpoint   text primary key,
    p256dh     text not null,
    auth       text not null,
    device_id  uuid not null,
    created_at timestamptz not null default now(),
    constraint push_endpoint_https check (endpoint like 'https://%')
);

alter table mox.push_subscriptions enable row level security;
grant select, insert, update, delete on mox.push_subscriptions to authenticated;
grant all on mox.push_subscriptions to service_role;

drop policy if exists "owner manages push subscriptions" on mox.push_subscriptions;
create policy "owner manages push subscriptions" on mox.push_subscriptions
    for all to authenticated
    using ((select auth.uid()) = mox.owner_id())
    with check ((select auth.uid()) = mox.owner_id());

------------------------------------------------------------
-- mox.push_config: where the function lives and its shared secret.
-- No policies, so only the database owner and service_role can read it.
------------------------------------------------------------
create table if not exists mox.push_config (
    id           int primary key default 1,
    function_url text not null,
    secret       text not null,
    constraint push_config_singleton check (id = 1)
);
alter table mox.push_config enable row level security;
revoke all on mox.push_config from anon, authenticated;
grant all on mox.push_config to service_role;

------------------------------------------------------------
-- On every new item, ask the function to notify the other devices.
------------------------------------------------------------
create or replace function mox.notify_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    config mox.push_config;
    subscriptions jsonb;
begin
    select * into config from mox.push_config where id = 1;
    if not found then
        return new;
    end if;

    select coalesce(jsonb_agg(jsonb_build_object(
               'endpoint', s.endpoint,
               'keys', jsonb_build_object('p256dh', s.p256dh, 'auth', s.auth))), '[]'::jsonb)
      into subscriptions
      from mox.push_subscriptions s
     where s.device_id <> new.source_device_id;

    if jsonb_array_length(subscriptions) = 0 then
        return new;
    end if;

    -- A failed notification must never block sending the file.
    begin
        perform net.http_post(
            url := config.function_url,
            body := jsonb_build_object(
                'subscriptions', subscriptions,
                'item', jsonb_build_object(
                    'kind', new.kind,
                    'name', new.original_name,
                    'item_count', new.item_count,
                    'source_platform', new.source_platform,
                    'uploaded_at', new.uploaded_at)),
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'x-mox-secret', config.secret));
    exception when others then
        raise warning 'mox push skipped: %', sqlerrm;
    end;
    return new;
end;
$$;

revoke all on function mox.notify_push() from public, anon, authenticated;

drop trigger if exists notify_push on mox.current_file;
create trigger notify_push
    after insert or update on mox.current_file
    for each row execute function mox.notify_push();
