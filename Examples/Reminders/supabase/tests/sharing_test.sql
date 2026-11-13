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

-- Reads an invitation id as the table owner, so a test can pass it to a user who
-- cannot see the row.
create function tests.invitation(email text) returns table (id uuid)
language sql security definer as $$
  select id from public.list_invitations where invited_email = email;
$$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'owner@example.com'),
  ('00000000-0000-0000-0000-00000000000b', 'member@example.com'),
  ('00000000-0000-0000-0000-00000000000c', 'stranger@example.com');

-- Profiles ----------------------------------------------------------------------

select results_eq(
  $$ select email, display_name from public.profiles
     where id::text like '00000000-0000-0000-0000-00000000000_' order by email $$,
  $$ values ('member@example.com', 'member'), ('owner@example.com', 'owner'), ('stranger@example.com', 'stranger') $$,
  'a new user gets a profile named after the email local part'
);

select tests.login('owner@example.com');

select results_eq(
  $$ select email from public.profiles $$, $$ values ('owner@example.com') $$,
  'a user with no shared list sees only their own profile'
);

insert into public.lists (id, name) values ('10000000-0000-0000-0000-000000000001', 'Trip');

-- Invite ------------------------------------------------------------------------

select throws_ok(
  $$ insert into public.list_invitations (list_id, invited_email)
     values ('10000000-0000-0000-0000-000000000001', 'Member@Example.com') $$,
  '23514', null, 'an email that is not lower case is refused'
);

select throws_ok(
  $$ insert into public.list_invitations (list_id, invited_email)
     values ('10000000-0000-0000-0000-000000000001', 'owner@example.com') $$,
  'P0001', 'cannot_invite_self', 'the owner cannot invite their own email'
);

select lives_ok(
  $$ insert into public.list_invitations (list_id, invited_email)
     values ('10000000-0000-0000-0000-000000000001', 'member@example.com') $$,
  'owner invites a person'
);

select throws_ok(
  $$ insert into public.list_invitations (list_id, invited_email)
     values ('10000000-0000-0000-0000-000000000001', 'member@example.com') $$,
  '23505', null, 'a second pending invitation for the same email is refused'
);

select lives_ok(
  $$ insert into public.list_invitations (list_id, invited_email)
     values ('10000000-0000-0000-0000-000000000001', 'later@example.com') $$,
  'owner invites a person who has no account yet'
);

select is((select count(*) from public.list_invitations), 2::bigint, 'owner sees the invitations of the list');

select is_empty($$ select * from public.my_invitations() $$, 'owner has no incoming invitations');

-- Stranger ----------------------------------------------------------------------

select tests.login('stranger@example.com');

select is_empty($$ select 1 from public.list_invitations $$, 'stranger sees no invitations');
select is_empty($$ select * from public.my_invitations() $$, 'stranger has no incoming invitations');

select throws_ok(
  $$ insert into public.list_invitations (list_id, invited_email)
     values ('10000000-0000-0000-0000-000000000001', 'stranger@example.com') $$,
  '42501', null, 'stranger cannot invite to a list they do not own'
);

select throws_ok(
  $$ select public.accept_invitation((select id from tests.invitation('member@example.com'))) $$,
  'P0002', null, 'stranger cannot accept an invitation for another email'
);

select throws_ok(
  $$ select public.decline_invitation((select id from tests.invitation('member@example.com'))) $$,
  'P0002', null, 'stranger cannot decline an invitation for another email'
);

-- Invitee -----------------------------------------------------------------------

select tests.login('member@example.com');

select results_eq(
  $$ select list_name, inviter_name from public.my_invitations() $$,
  $$ values ('Trip', 'owner') $$,
  'invitee sees the list name and the inviter name'
);

select is_empty($$ select 1 from public.lists $$, 'invitee cannot read the list before acceptance');

delete from public.list_invitations;
select is((select count(*) from public.list_invitations), 1::bigint, 'invitee cannot delete the invitation');

select lives_ok(
  $$ select public.accept_invitation((select id from tests.invitation('member@example.com'))) $$,
  'invitee accepts'
);

select isnt_empty($$ select 1 from public.lists where name = 'Trip' $$, 'the new member reads the list');
select is_empty($$ select * from public.my_invitations() $$, 'an accepted invitation is no longer incoming');

select results_eq(
  $$ select email from public.profiles order by email $$,
  $$ values ('member@example.com'), ('owner@example.com') $$,
  'people who share a list see each other''s profile'
);

select throws_ok(
  $$ select public.accept_invitation((select id from tests.invitation('member@example.com'))) $$,
  'P0002', null, 'an invitation cannot be accepted two times'
);

-- Owner again -------------------------------------------------------------------

select tests.login('owner@example.com');

select is(
  (select status::text from public.list_invitations where invited_email = 'member@example.com'),
  'accepted', 'owner sees the accepted status'
);

select throws_ok(
  $$ insert into public.list_invitations (list_id, invited_email)
     values ('10000000-0000-0000-0000-000000000001', 'member@example.com') $$,
  'P0001', 'already_member', 'a member cannot be invited again'
);

delete from public.list_members where user_id = '00000000-0000-0000-0000-00000000000b';

select lives_ok(
  $$ insert into public.list_invitations (list_id, invited_email)
     values ('10000000-0000-0000-0000-000000000001', 'member@example.com') $$,
  'a removed member can be invited again'
);

select is(
  (select status::text from public.list_invitations where invited_email = 'member@example.com'),
  'pending', 'the new invitation replaces the old one'
);

-- Decline -----------------------------------------------------------------------

select tests.login('member@example.com');

select lives_ok(
  $$ select public.decline_invitation((select id from tests.invitation('member@example.com'))) $$,
  'invitee declines'
);

select is_empty($$ select 1 from public.lists $$, 'a declined invitation gives no access');
select is_empty($$ select * from public.my_invitations() $$, 'a declined invitation is no longer incoming');

-- Revoke ------------------------------------------------------------------------

select tests.login('owner@example.com');

delete from public.list_invitations where invited_email = 'later@example.com';

select is_empty(
  $$ select 1 from public.list_invitations where invited_email = 'later@example.com' $$,
  'owner revokes a pending invitation'
);

-- API surface -------------------------------------------------------------------

select tests.login_anon();

select throws_ok($$ select * from public.my_invitations() $$, '42501', null, 'anon cannot call my_invitations');
select throws_ok(
  $$ select public.accept_invitation('10000000-0000-0000-0000-000000000001') $$,
  '42501', null, 'anon cannot call accept_invitation'
);

select tests.logout();

select * from finish();

rollback;
