SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION private.path_reminder_id (
  object_name text
)
  RETURNS uuid
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case
    when object_name ~ '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}/[^/]+$'
      then split_part(object_name, '/', 1)::uuid
  end;
$function$;

CREATE POLICY "Owners and members add attachment files" ON "storage"."objects"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (((bucket_id = 'attachments'::text) AND ( SELECT private.has_reminder_access(private.path_reminder_id(objects.name)) AS has_reminder_access)));

CREATE POLICY "Owners and members delete attachment files" ON "storage"."objects"
  FOR DELETE
  TO "authenticated"
  USING (((bucket_id = 'attachments'::text) AND ( SELECT private.has_reminder_access(private.path_reminder_id(objects.name)) AS has_reminder_access)));

CREATE POLICY "Owners and members read attachment files" ON "storage"."objects"
  FOR SELECT
  TO "authenticated"
  USING (((bucket_id = 'attachments'::text) AND ( SELECT private.has_reminder_access(private.path_reminder_id(objects.name)) AS has_reminder_access)));

ALTER PUBLICATION "supabase_realtime" ADD TABLE "public"."list_invitations";

ALTER PUBLICATION "supabase_realtime" ADD TABLE "public"."list_members";

ALTER PUBLICATION "supabase_realtime" ADD TABLE "public"."lists";

ALTER PUBLICATION "supabase_realtime" ADD TABLE "public"."reminder_attachments";

ALTER PUBLICATION "supabase_realtime" ADD TABLE "public"."reminders";

REVOKE ALL ON FUNCTION "private"."path_reminder_id"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."path_reminder_id"(text) TO "authenticated";
