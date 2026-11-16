-- Tables that the app follows with Realtime `postgres_changes`.
-- Row level security also applies to these events.
alter publication supabase_realtime add table public.lists;
alter publication supabase_realtime add table public.list_members;
alter publication supabase_realtime add table public.list_invitations;
alter publication supabase_realtime add table public.reminders;
alter publication supabase_realtime add table public.reminder_attachments;
