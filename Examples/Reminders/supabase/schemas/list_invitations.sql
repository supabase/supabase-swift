create type public.invitation_status as enum ('pending', 'accepted', 'declined');

create table public.list_invitations (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references public.lists (id) on delete cascade,
  invited_email text not null check (invited_email = lower(btrim(invited_email)) and invited_email <> ''),
  invited_by uuid not null default auth.uid() references auth.users (id) on delete cascade,
  status public.invitation_status not null default 'pending',
  created_at timestamptz not null default now(),
  unique (list_id, invited_email)
);

create index list_invitations_invited_email_idx on public.list_invitations (invited_email);
create index list_invitations_invited_by_idx on public.list_invitations (invited_by);

alter table public.list_invitations enable row level security;

-- The status changes only through `accept_invitation` and `decline_invitation`.
revoke all on table public.list_invitations from anon, authenticated;
grant select, delete on table public.list_invitations to authenticated;
grant insert (list_id, invited_email) on table public.list_invitations to authenticated;

create policy "Owners and invited users read invitations"
on public.list_invitations for select to authenticated
using (
  (select private.is_list_owner(list_id))
  or invited_email = lower((select auth.jwt()) ->> 'email')
);

create policy "Owners invite people to their lists"
on public.list_invitations for insert to authenticated
with check ((select private.is_list_owner(list_id)) and invited_by = (select auth.uid()));

create policy "Owners revoke invitations"
on public.list_invitations for delete to authenticated
using ((select private.is_list_owner(list_id)));
