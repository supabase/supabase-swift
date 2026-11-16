SET local check_function_bodies = off;

CREATE SCHEMA "private";

CREATE TABLE "public"."list_invitations" (
  "id"            uuid NOT NULL DEFAULT gen_random_uuid(),
  "list_id"       uuid NOT NULL,
  "invited_email" text NOT NULL,
  CONSTRAINT "list_invitations_invited_email_check" CHECK (((invited_email = lower(btrim(invited_email))) AND (invited_email <> ''::text))),
  CONSTRAINT "list_invitations_list_id_invited_email_key" UNIQUE (list_id, invited_email),
  CONSTRAINT "list_invitations_pkey" PRIMARY KEY (id),
  "invited_by"    uuid NOT NULL DEFAULT auth.uid()
);

ALTER TABLE "public"."list_invitations"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."list_invitations" FROM "anon";

CREATE TABLE "public"."list_members" (
  "list_id"    uuid                     NOT NULL,
  "user_id"    uuid                     NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "list_members_pkey" PRIMARY KEY (list_id, user_id)
);

ALTER TABLE "public"."list_members"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."list_members" FROM "anon";

CREATE TABLE "public"."lists" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "name"       text                     NOT NULL,
  "color"      text                     NOT NULL DEFAULT 'blue'::text,
  "icon"       text                     NOT NULL DEFAULT 'list.bullet'::text,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "lists_name_check" CHECK ((char_length(btrim(name)) > 0)),
  CONSTRAINT "lists_pkey" PRIMARY KEY (id),
  "owner_id"   uuid                     NOT NULL DEFAULT auth.uid()
);

ALTER TABLE "public"."lists"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."lists" FROM "anon";

CREATE TABLE "public"."profiles" (
  "id"           uuid                     NOT NULL,
  "email"        text                     NOT NULL,
  "display_name" text                     NOT NULL,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "profiles_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."profiles"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."profiles" FROM "anon";

CREATE TABLE "public"."reminder_attachments" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "reminder_id"  uuid                     NOT NULL,
  "storage_path" text                     NOT NULL,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "reminder_attachments_pkey" PRIMARY KEY (id),
  CONSTRAINT "reminder_attachments_storage_path_key" UNIQUE (storage_path),
  "created_by"   uuid                     DEFAULT auth.uid()
);

ALTER TABLE "public"."reminder_attachments"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."reminder_attachments" FROM "anon";

CREATE TABLE "public"."reminders" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "list_id"      uuid                     NOT NULL,
  "title"        text                     NOT NULL,
  "notes"        text                     NOT NULL DEFAULT ''::text,
  "due_at"       timestamp with time zone,
  "due_has_time" boolean                  NOT NULL DEFAULT false,
  "priority"     smallint                 NOT NULL DEFAULT 0,
  "is_flagged"   boolean                  NOT NULL DEFAULT false,
  "completed_at" timestamp with time zone,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "reminders_pkey" PRIMARY KEY (id),
  CONSTRAINT "reminders_priority_check" CHECK (((priority >= 0) AND (priority <= 3))),
  CONSTRAINT "reminders_title_check" CHECK ((char_length(btrim(title)) > 0)),
  "created_by"   uuid                     DEFAULT auth.uid()
);

ALTER TABLE "public"."reminders"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."reminders" FROM "anon";

CREATE TYPE "public"."invitation_status" AS ENUM (
  'pending',
  'accepted',
  'declined'
);

ALTER TABLE "public"."list_invitations"
  ADD COLUMN "status" public.invitation_status NOT NULL DEFAULT 'pending'::public.invitation_status;

ALTER TABLE "public"."list_invitations"
  ADD COLUMN "created_at" timestamp WITH time zone NOT NULL DEFAULT now();

CREATE OR REPLACE FUNCTION private.has_list_access (
  target_list_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select private.is_list_owner(target_list_id) or private.is_list_member(target_list_id);
$function$;

CREATE OR REPLACE FUNCTION private.has_reminder_access (
  target_reminder_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (
    select 1 from public.reminders
    where id = target_reminder_id and private.has_list_access(list_id)
  );
$function$;

CREATE OR REPLACE FUNCTION private.is_list_member (
  target_list_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (
    select 1 from public.list_members
    where list_id = target_list_id and user_id = (select auth.uid())
  );
$function$;

CREATE OR REPLACE FUNCTION private.is_list_owner (
  target_list_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (
    select 1 from public.lists
    where id = target_list_id and owner_id = (select auth.uid())
  );
$function$;

CREATE OR REPLACE FUNCTION private.set_updated_at()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.shares_list_with (
  other_user_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (
    select 1
    from public.lists l
    where private.has_list_access(l.id)
      and (
        l.owner_id = other_user_id
        or exists (
          select 1 from public.list_members m
          where m.list_id = l.id and m.user_id = other_user_id
        )
      )
  );
$function$;

ALTER TABLE "public"."list_members"
  ADD CONSTRAINT "list_members_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."list_invitations"
  ADD CONSTRAINT "list_invitations_list_id_fkey" FOREIGN KEY (list_id) REFERENCES public.lists(id) ON DELETE CASCADE;

ALTER TABLE "public"."list_members"
  ADD CONSTRAINT "list_members_list_id_fkey" FOREIGN KEY (list_id) REFERENCES public.lists(id) ON DELETE CASCADE;

ALTER TABLE "public"."profiles"
  ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."reminders"
  ADD CONSTRAINT "reminders_list_id_fkey" FOREIGN KEY (list_id) REFERENCES public.lists(id) ON DELETE CASCADE;

ALTER TABLE "public"."reminder_attachments"
  ADD CONSTRAINT "reminder_attachments_reminder_id_fkey" FOREIGN KEY (reminder_id) REFERENCES public.reminders(id) ON DELETE CASCADE;

CREATE INDEX list_invitations_invited_email_idx ON public.list_invitations USING btree (invited_email);

CREATE INDEX list_members_user_id_idx ON public.list_members USING btree (user_id);

CREATE INDEX reminder_attachments_reminder_id_idx ON public.reminder_attachments USING btree (reminder_id);

CREATE INDEX reminders_list_id_idx ON public.reminders USING btree (list_id);

CREATE TRIGGER lists_set_updated_at
  BEFORE UPDATE ON public.lists
  FOR EACH ROW
  EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER reminders_set_updated_at
  BEFORE UPDATE ON public.reminders
  FOR EACH ROW
  EXECUTE FUNCTION private.set_updated_at();

CREATE POLICY "Owners and invited users read invitations" ON "public"."list_invitations"
  FOR SELECT
  TO "authenticated"
  USING ((( SELECT private.is_list_owner(list_invitations.list_id) AS is_list_owner) OR (invited_email = lower((( SELECT auth.jwt() AS jwt) ->> 'email'::text)))));

CREATE POLICY "Owners revoke invitations" ON "public"."list_invitations"
  FOR DELETE
  TO "authenticated"
  USING (( SELECT private.is_list_owner(list_invitations.list_id) AS is_list_owner));

CREATE POLICY "Owners and members read the members of a list" ON "public"."list_members"
  FOR SELECT
  TO "authenticated"
  USING (( SELECT private.has_list_access(list_members.list_id) AS has_list_access));

CREATE POLICY "Owners remove members and members leave" ON "public"."list_members"
  FOR DELETE
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.is_list_owner(list_members.list_id) AS is_list_owner)));

CREATE POLICY "Users read their own profile and profiles of people they share " ON "public"."profiles"
  FOR SELECT
  TO "authenticated"
  USING (((id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.shares_list_with(profiles.id) AS shares_list_with)));

CREATE POLICY "Users update their own profile" ON "public"."profiles"
  FOR UPDATE
  TO "authenticated"
  USING ((id = ( SELECT auth.uid() AS uid)))
  WITH CHECK ((id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "Owners and members add attachments" ON "public"."reminder_attachments"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (( SELECT private.has_reminder_access(reminder_attachments.reminder_id) AS has_reminder_access));

CREATE POLICY "Owners and members delete attachments" ON "public"."reminder_attachments"
  FOR DELETE
  TO "authenticated"
  USING (( SELECT private.has_reminder_access(reminder_attachments.reminder_id) AS has_reminder_access));

CREATE POLICY "Owners and members read attachments" ON "public"."reminder_attachments"
  FOR SELECT
  TO "authenticated"
  USING (( SELECT private.has_reminder_access(reminder_attachments.reminder_id) AS has_reminder_access));

CREATE POLICY "Owners and members create reminders" ON "public"."reminders"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (( SELECT private.has_list_access(reminders.list_id) AS has_list_access));

CREATE POLICY "Owners and members delete reminders" ON "public"."reminders"
  FOR DELETE
  TO "authenticated"
  USING (( SELECT private.has_list_access(reminders.list_id) AS has_list_access));

CREATE POLICY "Owners and members read reminders" ON "public"."reminders"
  FOR SELECT
  TO "authenticated"
  USING (( SELECT private.has_list_access(reminders.list_id) AS has_list_access));

CREATE POLICY "Owners and members update reminders" ON "public"."reminders"
  FOR UPDATE
  TO "authenticated"
  USING (( SELECT private.has_list_access(reminders.list_id) AS has_list_access))
  WITH CHECK (( SELECT private.has_list_access(reminders.list_id) AS has_list_access));

REVOKE ALL ON FUNCTION "private"."has_list_access"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."has_list_access"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "private"."has_reminder_access"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."has_reminder_access"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "private"."is_list_member"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."is_list_member"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "private"."is_list_owner"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."is_list_owner"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "private"."set_updated_at"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "private"."shares_list_with"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."shares_list_with"(uuid) TO "authenticated";

GRANT USAGE ON SCHEMA "private" TO "authenticated";

REVOKE ALL ON TABLE "public"."list_invitations" FROM "authenticated";

REVOKE ALL ("invited_email") ON TABLE "public"."list_invitations" FROM "authenticated";

GRANT INSERT ("invited_email") ON TABLE "public"."list_invitations" TO "authenticated";

REVOKE ALL ("list_id") ON TABLE "public"."list_invitations" FROM "authenticated";

GRANT INSERT ("list_id") ON TABLE "public"."list_invitations" TO "authenticated";

GRANT DELETE, SELECT ON TABLE "public"."list_invitations" TO "authenticated";

REVOKE ALL ON TABLE "public"."list_invitations" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."list_invitations" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."list_invitations" TO "service_role";

REVOKE ALL ON TABLE "public"."list_members" FROM "authenticated";

GRANT DELETE, SELECT ON TABLE "public"."list_members" TO "authenticated";

REVOKE ALL ON TABLE "public"."list_members" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."list_members" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."list_members" TO "service_role";

REVOKE ALL ON TABLE "public"."lists" FROM "authenticated";

REVOKE ALL ("color") ON TABLE "public"."lists" FROM "authenticated";

GRANT UPDATE ("color") ON TABLE "public"."lists" TO "authenticated";

REVOKE ALL ("icon") ON TABLE "public"."lists" FROM "authenticated";

GRANT UPDATE ("icon") ON TABLE "public"."lists" TO "authenticated";

REVOKE ALL ("name") ON TABLE "public"."lists" FROM "authenticated";

GRANT UPDATE ("name") ON TABLE "public"."lists" TO "authenticated";

GRANT DELETE, INSERT, SELECT ON TABLE "public"."lists" TO "authenticated";

REVOKE ALL ON TABLE "public"."lists" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."lists" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."lists" TO "service_role";

REVOKE ALL ON TABLE "public"."profiles" FROM "authenticated";

REVOKE ALL ("display_name") ON TABLE "public"."profiles" FROM "authenticated";

GRANT UPDATE ("display_name") ON TABLE "public"."profiles" TO "authenticated";

GRANT SELECT ON TABLE "public"."profiles" TO "authenticated";

REVOKE ALL ON TABLE "public"."profiles" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."profiles" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."profiles" TO "service_role";

REVOKE ALL ON TABLE "public"."reminder_attachments" FROM "authenticated";

REVOKE ALL ("id") ON TABLE "public"."reminder_attachments" FROM "authenticated";

GRANT INSERT ("id") ON TABLE "public"."reminder_attachments" TO "authenticated";

REVOKE ALL ("reminder_id") ON TABLE "public"."reminder_attachments" FROM "authenticated";

GRANT INSERT ("reminder_id") ON TABLE "public"."reminder_attachments" TO "authenticated";

REVOKE ALL ("storage_path") ON TABLE "public"."reminder_attachments" FROM "authenticated";

GRANT INSERT ("storage_path") ON TABLE "public"."reminder_attachments" TO "authenticated";

GRANT DELETE, SELECT ON TABLE "public"."reminder_attachments" TO "authenticated";

REVOKE ALL ON TABLE "public"."reminder_attachments" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."reminder_attachments" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."reminder_attachments" TO "service_role";

REVOKE ALL ON TABLE "public"."reminders" FROM "authenticated";

REVOKE ALL ("completed_at") ON TABLE "public"."reminders" FROM "authenticated";

GRANT INSERT ("completed_at"), UPDATE ("completed_at") ON TABLE "public"."reminders" TO "authenticated";

REVOKE ALL ("due_at") ON TABLE "public"."reminders" FROM "authenticated";

GRANT INSERT ("due_at"), UPDATE ("due_at") ON TABLE "public"."reminders" TO "authenticated";

REVOKE ALL ("due_has_time") ON TABLE "public"."reminders" FROM "authenticated";

GRANT INSERT ("due_has_time"), UPDATE ("due_has_time") ON TABLE "public"."reminders" TO "authenticated";

REVOKE ALL ("id") ON TABLE "public"."reminders" FROM "authenticated";

GRANT INSERT ("id") ON TABLE "public"."reminders" TO "authenticated";

REVOKE ALL ("is_flagged") ON TABLE "public"."reminders" FROM "authenticated";

GRANT INSERT ("is_flagged"), UPDATE ("is_flagged") ON TABLE "public"."reminders" TO "authenticated";

REVOKE ALL ("list_id") ON TABLE "public"."reminders" FROM "authenticated";

GRANT INSERT ("list_id"), UPDATE ("list_id") ON TABLE "public"."reminders" TO "authenticated";

REVOKE ALL ("notes") ON TABLE "public"."reminders" FROM "authenticated";

GRANT INSERT ("notes"), UPDATE ("notes") ON TABLE "public"."reminders" TO "authenticated";

REVOKE ALL ("priority") ON TABLE "public"."reminders" FROM "authenticated";

GRANT INSERT ("priority"), UPDATE ("priority") ON TABLE "public"."reminders" TO "authenticated";

REVOKE ALL ("title") ON TABLE "public"."reminders" FROM "authenticated";

GRANT INSERT ("title"), UPDATE ("title") ON TABLE "public"."reminders" TO "authenticated";

GRANT DELETE, SELECT ON TABLE "public"."reminders" TO "authenticated";

REVOKE ALL ON TABLE "public"."reminders" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."reminders" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."reminders" TO "service_role";

ALTER TABLE "public"."list_invitations"
  ADD CONSTRAINT "list_invitations_invited_by_fkey" FOREIGN KEY (invited_by) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX list_invitations_invited_by_idx ON public.list_invitations USING btree (invited_by);

CREATE POLICY "Owners invite people to their lists" ON "public"."list_invitations"
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((( SELECT private.is_list_owner(list_invitations.list_id) AS is_list_owner) AND (invited_by = ( SELECT auth.uid() AS uid))));

ALTER TABLE "public"."lists"
  ADD CONSTRAINT "lists_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX lists_owner_id_idx ON public.lists USING btree (owner_id);

CREATE POLICY "Owners and members read lists" ON "public"."lists"
  FOR SELECT
  TO "authenticated"
  USING (((owner_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.is_list_member(lists.id) AS is_list_member)));

CREATE POLICY "Owners and members update lists" ON "public"."lists"
  FOR UPDATE
  TO "authenticated"
  USING (((owner_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.is_list_member(lists.id) AS is_list_member)))
  WITH CHECK (((owner_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.is_list_member(lists.id) AS is_list_member)));

CREATE POLICY "Owners delete lists" ON "public"."lists"
  FOR DELETE
  TO "authenticated"
  USING ((owner_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "Users create their own lists" ON "public"."lists"
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((owner_id = ( SELECT auth.uid() AS uid)));

ALTER TABLE "public"."reminder_attachments"
  ADD CONSTRAINT "reminder_attachments_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX reminder_attachments_created_by_idx ON public.reminder_attachments USING btree (created_by);

ALTER TABLE "public"."reminders"
  ADD CONSTRAINT "reminders_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX reminders_created_by_idx ON public.reminders USING btree (created_by);
