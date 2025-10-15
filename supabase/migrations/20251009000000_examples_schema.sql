-- Examples App Schema
-- This migration creates all tables and policies needed for the Supabase Swift Examples app

-- Todos table for demonstrating basic CRUD operations
create table if not exists todos(
    id uuid default gen_random_uuid() primary key,
    description text not null,
    is_complete boolean not null default false,
    created_at timestamptz default now() not null,
    owner_id uuid references auth.users(id) on delete cascade not null
);

-- Enable Row Level Security
alter table todos enable row level security;

-- Policies for todos
create policy "Users can view their own todos"
    on todos for select
    to authenticated
    using (auth.uid() = owner_id);

create policy "Users can insert their own todos"
    on todos for insert
    to authenticated
    with check (auth.uid() = owner_id);

create policy "Users can update their own todos"
    on todos for update
    to authenticated
    using (auth.uid() = owner_id)
    with check (auth.uid() = owner_id);

create policy "Users can delete their own todos"
    on todos for delete
    to authenticated
    using (auth.uid() = owner_id);

-- Profiles table for user profile management
create table if not exists profiles(
    id uuid references auth.users(id) on delete cascade primary key,
    username text unique,
    full_name text,
    avatar_url text,
    website text,
    updated_at timestamptz default now() not null
);

-- Enable Row Level Security
alter table profiles enable row level security;

-- Policies for profiles
create policy "Public profiles are viewable by everyone"
    on profiles for select
    using (true);

create policy "Users can insert their own profile"
    on profiles for insert
    to authenticated
    with check (auth.uid() = id);

create policy "Users can update their own profile"
    on profiles for update
    to authenticated
    using (auth.uid() = id);

-- Messages table for demonstrating realtime subscriptions
create table if not exists messages(
    id uuid default gen_random_uuid() primary key,
    content text not null,
    user_id uuid references auth.users(id) on delete cascade not null,
    channel_id text not null default 'general',
    created_at timestamptz default now() not null
);

-- Enable Row Level Security
alter table messages enable row level security;

-- Policies for messages
create policy "Messages are viewable by authenticated users"
    on messages for select
    to authenticated
    using (true);

create policy "Authenticated users can insert messages"
    on messages for insert
    to authenticated
    with check (auth.uid() = user_id);

-- Add messages to realtime publication
alter publication supabase_realtime add table messages;
alter publication supabase_realtime add table todos;
alter publication supabase_realtime add table profiles;

-- Storage policies for the Examples app
create policy "Authenticated users can create buckets"
    on storage.buckets for insert
    to authenticated
    with check (true);

create policy "Authenticated users can view buckets"
    on storage.buckets for select
    to authenticated
    using (true);

create policy "Authenticated users can update buckets"
    on storage.buckets for update
    to authenticated
    using (true);

create policy "Authenticated users can delete buckets"
    on storage.buckets for delete
    to authenticated
    using (true);

create policy "Authenticated users can upload objects"
    on storage.objects for insert
    to authenticated
    with check (true);

create policy "Authenticated users can view objects"
    on storage.objects for select
    to authenticated
    using (true);

create policy "Authenticated users can update objects"
    on storage.objects for update
    to authenticated
    using (true);

create policy "Authenticated users can delete objects"
    on storage.objects for delete
    to authenticated
    using (true);

-- Function to demonstrate RPC calls
create or replace function hello_world(name text default 'World')
returns json
language plpgsql
as $$
begin
  return json_build_object(
    'message', 'Hello ' || name || '!',
    'timestamp', now()
  );
end;
$$;

-- Function to demonstrate RPC with complex return types
create or replace function get_user_stats()
returns table(
  user_id uuid,
  todo_count bigint,
  message_count bigint,
  last_activity timestamptz
)
language plpgsql
security definer
as $$
begin
  return query
  select
    auth.uid(),
    (select count(*) from todos where owner_id = auth.uid()),
    (select count(*) from messages where user_id = auth.uid()),
    greatest(
      (select max(created_at) from todos where owner_id = auth.uid()),
      (select max(created_at) from messages where user_id = auth.uid())
    );
end;
$$;

-- Trigger to update updated_at on profiles
create or replace function update_modified_column()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger update_profiles_modtime
  before update on profiles
  for each row
  execute procedure update_modified_column();
