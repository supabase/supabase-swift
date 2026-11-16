create table public.lists (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null check (char_length(btrim(name)) > 0),
  color text not null default 'blue',
  icon text not null default 'list.bullet',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index lists_owner_id_idx on public.lists (owner_id);

create trigger lists_set_updated_at
before update on public.lists
for each row execute function private.set_updated_at();

alter table public.lists enable row level security;

-- Members can change how a list looks. They cannot change its owner.
revoke all on table public.lists from anon, authenticated;
grant select, insert, delete on table public.lists to authenticated;
grant update (name, color, icon) on table public.lists to authenticated;

-- The owner check reads the row itself. `insert … returning` needs this: a helper that
-- queries the table cannot see the row that the same statement inserts.
create policy "Owners and members read lists"
on public.lists for select to authenticated
using (owner_id = (select auth.uid()) or (select private.is_list_member(id)));

create policy "Users create their own lists"
on public.lists for insert to authenticated
with check (owner_id = (select auth.uid()));

create policy "Owners and members update lists"
on public.lists for update to authenticated
using (owner_id = (select auth.uid()) or (select private.is_list_member(id)))
with check (owner_id = (select auth.uid()) or (select private.is_list_member(id)));

create policy "Owners delete lists"
on public.lists for delete to authenticated
using (owner_id = (select auth.uid()));
