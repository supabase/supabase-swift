begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

-- Test identities and helpers -------------------------------------------------

create schema tests;
grant usage on schema tests to anon, authenticated;

create function tests.login(user_email text) returns void
language plpgsql as $$
declare
  uid uuid;
begin
  perform set_config('role', 'postgres', true);
  select id into strict uid from auth.users where email = user_email;
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', uid, 'email', user_email, 'role', 'authenticated')::text,
    true
  );
  perform set_config('role', 'authenticated', true);
end $$;

create function tests.login_anon() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('role', 'anon', true);
end $$;

create function tests.logout() returns void
language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'owner@example.com'),
  ('00000000-0000-0000-0000-00000000000b', 'member@example.com'),
  ('00000000-0000-0000-0000-00000000000c', 'stranger@example.com');

insert into public.lists (id, owner_id, name)
values ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'Trip');

insert into public.list_members (list_id, user_id)
values ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b');

insert into public.reminders (id, list_id, title)
values ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Passport');

-- Storage ---------------------------------------------------------------------

select tests.login('owner@example.com');

select lives_ok(
  $$ insert into storage.objects (bucket_id, name)
     values ('attachments', '20000000-0000-0000-0000-000000000001/a.jpg') $$,
  'owner uploads to a reminder folder'
);

select tests.login('member@example.com');

select lives_ok(
  $$ insert into storage.objects (bucket_id, name)
     values ('attachments', '20000000-0000-0000-0000-000000000001/b.jpg') $$,
  'member uploads to a reminder folder'
);

select is(
  (select count(*) from storage.objects
   where bucket_id = 'attachments' and name like '20000000-0000-0000-0000-00000000000_/%'), 2::bigint,
  'member reads the objects of the reminder'
);

select throws_ok(
  $$ insert into storage.objects (bucket_id, name) values ('attachments', 'not-a-uuid/c.jpg') $$,
  '42501', null, 'a folder that is not a reminder id is refused'
);

select throws_ok(
  $$ insert into storage.objects (bucket_id, name) values ('attachments', 'c.jpg') $$,
  '42501', null, 'an object with no folder is refused'
);

select throws_ok(
  $$ insert into storage.objects (bucket_id, name)
     values ('attachments', '99999999-0000-0000-0000-000000000001/c.jpg') $$,
  '42501', null, 'a folder of an unknown reminder is refused'
);

select tests.login('stranger@example.com');

select throws_ok(
  $$ insert into storage.objects (bucket_id, name)
     values ('attachments', '20000000-0000-0000-0000-000000000001/c.jpg') $$,
  '42501', null, 'stranger cannot upload to the reminder folder'
);

select is_empty($$ select 1 from storage.objects $$, 'stranger reads no objects');

-- Storage refuses SQL deletes unless this setting is on. The Storage API sets it.
-- Row level security still applies.
set local storage.allow_delete_query = 'true';

delete from storage.objects where bucket_id = 'attachments';
select tests.logout();
select is(
  (select count(*) from storage.objects
   where bucket_id = 'attachments' and name like '20000000-0000-0000-0000-00000000000_/%'), 2::bigint,
  'stranger cannot delete objects'
);

select tests.login('member@example.com');
delete from storage.objects where name = '20000000-0000-0000-0000-000000000001/a.jpg';
select tests.logout();
select is(
  (select count(*) from storage.objects
   where bucket_id = 'attachments' and name like '20000000-0000-0000-0000-00000000000_/%'), 1::bigint,
  'member deletes an object'
);

-- Realtime --------------------------------------------------------------------

select is(
  (select array_agg(tablename::text order by tablename::text collate "C")
   from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public'),
  array['list_invitations', 'list_members', 'lists', 'reminder_attachments', 'reminders'],
  'the five synced tables are in the realtime publication'
);

select * from finish();

rollback;
