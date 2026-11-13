SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION private.handle_new_user()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  insert into public.profiles (id, email, display_name)
  values (new.id, lower(new.email), split_part(new.email, '@', 1));
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.validate_invitation()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.accept_invitation (
  invitation_id uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

REVOKE ALL ON FUNCTION "public"."accept_invitation"(uuid) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.decline_invitation (
  invitation_id uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

REVOKE ALL ON FUNCTION "public"."decline_invitation"(uuid) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.my_invitations()
  RETURNS TABLE (
    id           uuid,
    list_name    text,
    inviter_name text
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select i.id, l.name, p.display_name
  from public.list_invitations i
  join public.lists l on l.id = i.list_id
  join public.profiles p on p.id = i.invited_by
  where i.status = 'pending'
    and i.invited_email = lower((select auth.jwt()) ->> 'email')
  order by i.created_at;
$function$;

REVOKE ALL ON FUNCTION "public"."my_invitations"() FROM PUBLIC, "anon";

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION private.handle_new_user();

CREATE TRIGGER list_invitations_validate
  BEFORE INSERT ON public.list_invitations
  FOR EACH ROW
  EXECUTE FUNCTION private.validate_invitation();

REVOKE ALL ON FUNCTION "private"."handle_new_user"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "private"."validate_invitation"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."accept_invitation"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."accept_invitation"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."accept_invitation"(uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."accept_invitation"(uuid) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."decline_invitation"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."decline_invitation"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."decline_invitation"(uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."decline_invitation"(uuid) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."my_invitations"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."my_invitations"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."my_invitations"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."my_invitations"() TO "service_role";
