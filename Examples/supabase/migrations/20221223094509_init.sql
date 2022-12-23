create table todos (
    id uuid default uuid_generate_v4 () primary key not null,
    description text not null,
    is_complete boolean not null,
    created_at timestamptz default (now() at time zone 'utc'::text) not null
);

