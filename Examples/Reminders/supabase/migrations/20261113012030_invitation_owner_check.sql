SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION private.validate_invitation()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  -- A before trigger runs before the row level security check of the insert. Without
  -- this check, the errors below would tell any user who owns a list and who is a
  -- member of it.
  if (select auth.uid()) is not null and not private.is_list_owner(new.list_id) then
    raise exception 'permission denied for table list_invitations' using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.lists l
    join public.profiles p on p.id = l.owner_id
    where l.id = new.list_id and p.email = new.invited_email
  ) then
    raise exception 'cannot_invite_self';
  end if;

  if exists (
    select 1
    from public.list_members m
    join public.profiles p on p.id = m.user_id
    where m.list_id = new.list_id and p.email = new.invited_email
  ) then
    raise exception 'already_member';
  end if;

  -- An answered invitation must not block a new one, for example after a member leaves.
  delete from public.list_invitations
  where list_id = new.list_id
    and invited_email = new.invited_email
    and status <> 'pending';

  return new;
end;
$function$;
