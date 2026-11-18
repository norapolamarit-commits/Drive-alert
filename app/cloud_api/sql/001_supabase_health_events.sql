-- Run in the existing Doz Supabase project's SQL Editor before enabling sync.
-- The API is the only writer/reader. Browser and mobile clients get no table policy.
create table if not exists public.doz_health_events (
  event_id text primary key check (event_id ~ '^[0-9a-f]{64}$'),
  kind text not null check (kind in ('sensor_events', 'alert_events')),
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null check (length(device_id) between 1 and 128),
  received_at timestamptz not null default now(),
  event_json jsonb not null check (jsonb_typeof(event_json) = 'object')
);

create index if not exists doz_health_events_owner_kind_time_idx
  on public.doz_health_events (auth_user_id, kind, received_at desc);

alter table public.doz_health_events enable row level security;
revoke all on public.doz_health_events from anon, authenticated;
grant select, insert, delete on public.doz_health_events to service_role;
