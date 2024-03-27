create table store(
    "key" text primary key,
    "value" jsonb not null
);

alter publication supabase_realtime
    add table store;

