-- One image of a reminder. The file is in the `attachments` Storage bucket at
-- `storage_path`, which is `{reminder_id}/{uuid}.jpg`.
create table public.reminder_attachments (
  id uuid primary key default gen_random_uuid(),
  reminder_id uuid not null references public.reminders (id) on delete cascade,
  storage_path text not null unique,
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

create index reminder_attachments_reminder_id_idx on public.reminder_attachments (reminder_id);
create index reminder_attachments_created_by_idx on public.reminder_attachments (created_by);

alter table public.reminder_attachments enable row level security;

revoke all on table public.reminder_attachments from anon, authenticated;
grant select, delete on table public.reminder_attachments to authenticated;
grant insert (id, reminder_id, storage_path) on table public.reminder_attachments to authenticated;

create policy "Owners and members read attachments"
on public.reminder_attachments for select to authenticated
using ((select private.has_reminder_access(reminder_id)));

create policy "Owners and members add attachments"
on public.reminder_attachments for insert to authenticated
with check ((select private.has_reminder_access(reminder_id)));

create policy "Owners and members delete attachments"
on public.reminder_attachments for delete to authenticated
using ((select private.has_reminder_access(reminder_id)));
