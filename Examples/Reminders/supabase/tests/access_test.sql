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

-- Owner -----------------------------------------------------------------------

select tests.login('owner@example.com');

select lives_ok(
  $$ insert into public.lists (id, name) values ('10000000-0000-0000-0000-000000000001', 'Groceries') $$,
  'owner creates a list'
);

select is(
  (select owner_id from public.lists where id = '10000000-0000-0000-0000-000000000001'),
  '00000000-0000-0000-0000-00000000000a'::uuid,
  'owner_id defaults to the caller'
);

select throws_ok(
  $$ insert into public.lists (name) values ('   ') $$,
  '23514', null, 'a list name of only spaces is refused'
);

select throws_ok(
  $$ insert into public.lists (name, owner_id) values ('Stolen', '00000000-0000-0000-0000-00000000000b') $$,
  '42501', null, 'a list cannot be created for another owner'
);

select lives_ok(
  $$ insert into public.reminders (id, list_id, title)
     values ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Milk') $$,
  'owner creates a reminder'
);

select throws_ok(
  $$ insert into public.reminders (list_id, title) values ('10000000-0000-0000-0000-000000000001', '  ') $$,
  '23514', null, 'a reminder title of only spaces is refused'
);

select throws_ok(
  $$ insert into public.reminders (list_id, title, priority)
     values ('10000000-0000-0000-0000-000000000001', 'Bad', 4) $$,
  '23514', null, 'priority above 3 is refused'
);

select lives_ok(
  $$ insert into public.reminder_attachments (reminder_id, storage_path)
     values ('20000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001/z.jpg') $$,
  'owner adds an attachment row'
);

-- Stranger --------------------------------------------------------------------

select tests.login('stranger@example.com');

select is_empty($$ select 1 from public.lists $$, 'stranger sees no lists');
select is_empty($$ select 1 from public.reminders $$, 'stranger sees no reminders');
select is_empty($$ select 1 from public.list_members $$, 'stranger sees no members');
select is_empty($$ select 1 from public.reminder_attachments $$, 'stranger sees no attachments');
select is_empty($$ select 1 from public.list_invitations $$, 'stranger sees no invitations');

select throws_ok(
  $$ insert into public.reminders (list_id, title) values ('10000000-0000-0000-0000-000000000001', 'Spam') $$,
  '42501', null, 'stranger cannot add a reminder to the list'
);

select throws_ok(
  $$ insert into public.list_members (list_id, user_id)
     values ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000c') $$,
  '42501', null, 'a user cannot add a member row directly'
);

-- Anonymous -------------------------------------------------------------------

select tests.login_anon();

select throws_ok($$ select 1 from public.lists $$, '42501', null, 'anon has no access to lists');
select throws_ok($$ select 1 from public.reminders $$, '42501', null, 'anon has no access to reminders');
select throws_ok($$ select 1 from public.profiles $$, '42501', null, 'anon has no access to profiles');

-- Member ----------------------------------------------------------------------

select tests.logout();

insert into public.list_members (list_id, user_id) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b'),
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000c');

select tests.login('member@example.com');

select isnt_empty($$ select 1 from public.lists $$, 'member sees the list');
select isnt_empty($$ select 1 from public.reminders $$, 'member sees the reminders');
select is(
  (select count(*) from public.list_members), 2::bigint,
  'member sees the member rows of the list'
);

select lives_ok(
  $$ insert into public.reminders (id, list_id, title)
     values ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'Bread') $$,
  'member creates a reminder'
);

select is(
  (select created_by from public.reminders where id = '20000000-0000-0000-0000-000000000002'),
  '00000000-0000-0000-0000-00000000000b'::uuid,
  'created_by defaults to the caller'
);

update public.reminders set title = 'Rye bread'
where id = '20000000-0000-0000-0000-000000000002';

select is(
  (select title from public.reminders where id = '20000000-0000-0000-0000-000000000002'),
  'Rye bread', 'member updates a reminder'
);

select throws_ok(
  $$ update public.reminders set updated_at = '2000-01-01', created_by = null
     where id = '20000000-0000-0000-0000-000000000002' $$,
  '42501', null, 'server-owned reminder columns cannot be written'
);

select tests.logout();
update public.reminders set updated_at = '2000-01-01' where id = '20000000-0000-0000-0000-000000000002';
select cmp_ok(
  (select updated_at from public.reminders where id = '20000000-0000-0000-0000-000000000002'),
  '>', '2020-01-01'::timestamptz, 'updated_at is set by a trigger on every update'
);
select tests.login('member@example.com');

update public.lists set name = 'Food' where id = '10000000-0000-0000-0000-000000000001';

select is(
  (select name from public.lists where id = '10000000-0000-0000-0000-000000000001'),
  'Food', 'member renames the list'
);

select throws_ok(
  $$ update public.lists set owner_id = '00000000-0000-0000-0000-00000000000b'
     where id = '10000000-0000-0000-0000-000000000001' $$,
  '42501', null, 'member cannot take ownership of the list'
);

delete from public.reminders where id = '20000000-0000-0000-0000-000000000002';

select is_empty(
  $$ select 1 from public.reminders where id = '20000000-0000-0000-0000-000000000002' $$,
  'member deletes a reminder'
);

delete from public.lists where id = '10000000-0000-0000-0000-000000000001';

select isnt_empty(
  $$ select 1 from public.lists where id = '10000000-0000-0000-0000-000000000001' $$,
  'member cannot delete the list'
);

delete from public.list_members where user_id = '00000000-0000-0000-0000-00000000000c';

select is(
  (select count(*) from public.list_members), 2::bigint,
  'member cannot remove another member'
);

delete from public.list_members where user_id = '00000000-0000-0000-0000-00000000000b';

select is_empty($$ select 1 from public.lists $$, 'member leaves the list and loses access');

-- Owner manages members and deletes the list -----------------------------------

select tests.login('owner@example.com');

delete from public.list_members where user_id = '00000000-0000-0000-0000-00000000000c';

select is_empty($$ select 1 from public.list_members $$, 'owner removes a member');

delete from public.lists where id = '10000000-0000-0000-0000-000000000001';

select tests.logout();

select is_empty($$ select 1 from public.lists $$, 'owner deletes the list');
select is_empty($$ select 1 from public.reminders $$, 'reminders go with the list');
select is_empty($$ select 1 from public.reminder_attachments $$, 'attachment rows go with the list');

select * from finish();

rollback;
