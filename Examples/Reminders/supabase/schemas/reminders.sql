create table public.reminders (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references public.lists (id) on delete cascade,
  title text not null check (char_length(btrim(title)) > 0),
  notes text not null default '',
  due_at timestamptz,
  -- False for a date with no time. `due_at` is then the start of that day on the device.
  due_has_time boolean not null default false,
  priority smallint not null default 0 check (priority between 0 and 3),
  is_flagged boolean not null default false,
  completed_at timestamptz,
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index reminders_list_id_idx on public.reminders (list_id);
create index reminders_created_by_idx on public.reminders (created_by);

create trigger reminders_set_updated_at
before update on public.reminders
for each row execute function private.set_updated_at();

alter table public.reminders enable row level security;

revoke all on table public.reminders from anon, authenticated;
grant select, delete on table public.reminders to authenticated;
grant insert (id, list_id, title, notes, due_at, due_has_time, priority, is_flagged, completed_at)
  on table public.reminders to authenticated;
grant update (list_id, title, notes, due_at, due_has_time, priority, is_flagged, completed_at)
  on table public.reminders to authenticated;

create policy "Owners and members read reminders"
on public.reminders for select to authenticated
using ((select private.has_list_access(list_id)));

create policy "Owners and members create reminders"
on public.reminders for insert to authenticated
with check ((select private.has_list_access(list_id)));

-- `with check` uses the new `list_id`, so a reminder can move only to a list
-- that the user can also open.
create policy "Owners and members update reminders"
on public.reminders for update to authenticated
using ((select private.has_list_access(list_id)))
with check ((select private.has_list_access(list_id)));

create policy "Owners and members delete reminders"
on public.reminders for delete to authenticated
using ((select private.has_list_access(list_id)));
