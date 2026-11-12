-- Helpers for row level security. They live in a schema that the API does not expose.
-- They are `security definer` so that a policy on one table can read another table
-- without recursion through that table's own policies.

create schema private;

revoke all on schema private from public;
grant usage on schema private to authenticated;

create function private.is_list_owner(target_list_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.lists
    where id = target_list_id and owner_id = (select auth.uid())
  );
$$;

create function private.is_list_member(target_list_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.list_members
    where list_id = target_list_id and user_id = (select auth.uid())
  );
$$;

create function private.has_list_access(target_list_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_list_owner(target_list_id) or private.is_list_member(target_list_id);
$$;

create function private.has_reminder_access(target_reminder_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.reminders
    where id = target_reminder_id and private.has_list_access(list_id)
  );
$$;

create function private.shares_list_with(other_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.lists l
    where private.has_list_access(l.id)
      and (
        l.owner_id = other_user_id
        or exists (
          select 1 from public.list_members m
          where m.list_id = l.id and m.user_id = other_user_id
        )
      )
  );
$$;

create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke all on function private.is_list_owner(uuid) from public, anon;
revoke all on function private.is_list_member(uuid) from public, anon;
revoke all on function private.has_list_access(uuid) from public, anon;
revoke all on function private.has_reminder_access(uuid) from public, anon;
revoke all on function private.shares_list_with(uuid) from public, anon;
revoke all on function private.set_updated_at() from public, anon, authenticated;

grant execute on function private.is_list_owner(uuid) to authenticated;
grant execute on function private.is_list_member(uuid) to authenticated;
grant execute on function private.has_list_access(uuid) to authenticated;
grant execute on function private.has_reminder_access(uuid) to authenticated;
grant execute on function private.shares_list_with(uuid) to authenticated;
