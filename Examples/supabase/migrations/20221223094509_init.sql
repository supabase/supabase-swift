create table todos(
    id uuid default uuid_generate_v4() primary key not null,
    description text not null,
    is_complete boolean not null,
    created_at timestamptz default (now() at time zone 'utc'::text) not null,
    owner_id uuid references auth.users(id) not null
);

alter table todos enable row level security;

create policy "Allow access to owner only" on todos as permissive
    for all to authenticated
        using (auth.uid() = owner_id)
        with check (auth.uid() = owner_id);

-- Storage
create policy "Allow authenticated users to create buckets." on storage.buckets
    for insert to authenticated
        with check (true);

create policy "Allow authenticated users to list buckets." on storage.buckets
    for select to authenticated
        using (true);

create policy "Allow authenticated users to upload objects." on storage.objects
    for insert to authenticated
        with check (true);

create policy "Allow authenticated users to list objects." on storage.objects
    for select to authenticated
        using (true);

