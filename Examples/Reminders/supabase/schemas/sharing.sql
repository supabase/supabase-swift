-- Invitation rules that a check constraint cannot express.
create function private.validate_invitation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
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
$$;

revoke all on function private.validate_invitation() from public, anon, authenticated;

create trigger list_invitations_validate
before insert on public.list_invitations
for each row execute function private.validate_invitation();

-- The pending invitations for the caller. The caller cannot read `lists` or the
-- inviter's profile before acceptance, so a plain select cannot return these names.
create function public.my_invitations()
returns table (id uuid, list_name text, inviter_name text)
language sql
stable
security definer
set search_path = ''
as $$
  select i.id, l.name, p.display_name
  from public.list_invitations i
  join public.lists l on l.id = i.list_id
  join public.profiles p on p.id = i.invited_by
  where i.status = 'pending'
    and i.invited_email = lower((select auth.jwt()) ->> 'email')
  order by i.created_at;
$$;

create function public.accept_invitation(invitation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_list_id uuid;
begin
  select list_id into target_list_id
  from public.list_invitations
  where id = invitation_id
    and status = 'pending'
    and invited_email = lower((select auth.jwt()) ->> 'email')
  for update;

  if target_list_id is null then
    raise exception 'invitation_not_found' using errcode = 'P0002';
  end if;

  insert into public.list_members (list_id, user_id)
  values (target_list_id, (select auth.uid()))
  on conflict do nothing;

  update public.list_invitations set status = 'accepted' where id = invitation_id;
end;
$$;

create function public.decline_invitation(invitation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.list_invitations
  set status = 'declined'
  where id = invitation_id
    and status = 'pending'
    and invited_email = lower((select auth.jwt()) ->> 'email');

  if not found then
    raise exception 'invitation_not_found' using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.my_invitations() from public, anon;
revoke all on function public.accept_invitation(uuid) from public, anon;
revoke all on function public.decline_invitation(uuid) from public, anon;

grant execute on function public.my_invitations() to authenticated;
grant execute on function public.accept_invitation(uuid) to authenticated;
grant execute on function public.decline_invitation(uuid) to authenticated;
