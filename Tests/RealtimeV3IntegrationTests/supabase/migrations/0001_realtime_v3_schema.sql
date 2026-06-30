-- RealtimeV3 integration test schema
-- Comprehensive realtime-enabled schema for IE test suite.

-- messages table: primary target for postgres-changes e2e tests
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null,
  content text not null,
  user_id uuid,
  created_at timestamptz not null default now()
);

-- REPLICA IDENTITY FULL so UPDATE/DELETE carry old_record for postgres-changes tests
alter table public.messages replica identity full;

-- Add to realtime publication so postgres-changes subscriptions receive events
alter publication supabase_realtime add table public.messages;

-- Enable Row Level Security
alter table public.messages enable row level security;

-- Permissive RLS policies for the test anon role (this is a test DB, not production)
create policy "anon can select messages"
  on public.messages for select
  to anon, authenticated
  using (true);

create policy "anon can insert messages"
  on public.messages for insert
  to anon, authenticated
  with check (true);

create policy "anon can update messages"
  on public.messages for update
  to anon, authenticated
  using (true)
  with check (true);

create policy "anon can delete messages"
  on public.messages for delete
  to anon, authenticated
  using (true);

-- Explicit privilege grants (required since Supabase no longer grants public schema by default)
grant all on table public.messages to anon, authenticated;

-- presence_demo table: secondary table for future presence e2e tests
create table if not exists public.presence_demo (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  channel_name text not null,
  metadata jsonb,
  last_seen_at timestamptz not null default now()
);

alter table public.presence_demo replica identity full;
alter publication supabase_realtime add table public.presence_demo;

alter table public.presence_demo enable row level security;

create policy "anon can select presence_demo"
  on public.presence_demo for select
  to anon, authenticated
  using (true);

create policy "anon can insert presence_demo"
  on public.presence_demo for insert
  to anon, authenticated
  with check (true);

create policy "anon can update presence_demo"
  on public.presence_demo for update
  to anon, authenticated
  using (true)
  with check (true);

create policy "anon can delete presence_demo"
  on public.presence_demo for delete
  to anon, authenticated
  using (true);

grant all on table public.presence_demo to anon, authenticated;
