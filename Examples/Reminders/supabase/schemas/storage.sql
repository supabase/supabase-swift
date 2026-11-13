-- Rules for the private `attachments` bucket. The bucket itself is declared in
-- `config.toml`. An object path is `{reminder_id}/{file name}`.

-- Returns the reminder id from the first path segment, or null if it is not a uuid.
-- A direct cast in the policy would raise an error and show the reason to the caller.
create function private.path_reminder_id(object_name text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case
    when object_name ~ '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}/[^/]+$'
      then split_part(object_name, '/', 1)::uuid
  end;
$$;

revoke all on function private.path_reminder_id(text) from public, anon;
grant execute on function private.path_reminder_id(text) to authenticated;

create policy "Owners and members read attachment files"
on storage.objects for select to authenticated
using (
  bucket_id = 'attachments'
  and (select private.has_reminder_access(private.path_reminder_id(name)))
);

create policy "Owners and members add attachment files"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'attachments'
  and (select private.has_reminder_access(private.path_reminder_id(name)))
);

create policy "Owners and members delete attachment files"
on storage.objects for delete to authenticated
using (
  bucket_id = 'attachments'
  and (select private.has_reminder_access(private.path_reminder_id(name)))
);
