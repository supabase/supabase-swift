create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  display_name text not null,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

revoke all on table public.profiles from anon, authenticated;
grant select on table public.profiles to authenticated;
grant update (display_name) on table public.profiles to authenticated;

create policy "Users read their own profile and profiles of people they share a list with"
on public.profiles for select to authenticated
using (id = (select auth.uid()) or (select private.shares_list_with(id)));

create policy "Users update their own profile"
on public.profiles for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));
