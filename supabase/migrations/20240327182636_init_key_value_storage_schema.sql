create table key_value_storage(
    "key" text primary key,
    "value" jsonb not null
);

alter publication supabase_realtime
    add table key_value_storage;

