-- The owner of a list is `lists.owner_id` and has no row here.
-- Rows are created only by `accept_invitation`.
create table public.list_members (
  list_id uuid not null references public.lists (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (list_id, user_id)
);

create index list_members_user_id_idx on public.list_members (user_id);

alter table public.list_members enable row level security;

revoke all on table public.list_members from anon, authenticated;
grant select, delete on table public.list_members to authenticated;

create policy "Owners and members read the members of a list"
on public.list_members for select to authenticated
using ((select private.has_list_access(list_id)));

create policy "Owners remove members and members leave"
on public.list_members for delete to authenticated
using (user_id = (select auth.uid()) or (select private.is_list_owner(list_id)));
