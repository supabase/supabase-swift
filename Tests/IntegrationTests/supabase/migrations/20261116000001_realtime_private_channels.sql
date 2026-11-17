-- RealtimeBroadcastOptionsIntegrationTests: broadcast replay works only on private channels, and
-- a private channel needs a policy on `realtime.messages` for each action.
--
-- The policies cover only topics that start with `swift-private:`, and only the `authenticated`
-- role, so `privateChannelWithoutAPolicyFailsAtOnce` (anon, `private-denied`) is still refused.
-- Topics under `swift-private:read-only:` can be read but not written, so a test can prove that
-- an acknowledged broadcast waits for the server.
--
-- The Realtime service creates `realtime.messages`, so a plain Postgres (the typegen fixtures'
-- container) has no table to put the policies on.
DO $do$
BEGIN
  IF to_regclass('realtime.messages') IS NOT NULL THEN
    CREATE POLICY "swift private channels: read"
    ON realtime.messages
    FOR SELECT
    TO authenticated
    USING (realtime.topic() LIKE 'swift-private:%');

    CREATE POLICY "swift private channels: write"
    ON realtime.messages
    FOR INSERT
    TO authenticated
    WITH CHECK (
      realtime.topic() LIKE 'swift-private:%'
      AND realtime.topic() NOT LIKE 'swift-private:read-only:%'
    );
  END IF;
END
$do$;

-- Replay returns only messages the database stored, which `realtime.send` does. A note whose body
-- starts with `swift-private:` broadcasts `note_inserted` on the private topic named by its body,
-- so a test can send a message that a later join replays. The function lives outside `public`,
-- so PostgREST and the typegen fixtures do not see it.
CREATE OR REPLACE FUNCTION realtime_test.broadcast_personal_note_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM realtime.send(
    jsonb_build_object('body', NEW.body),
    'note_inserted',
    NEW.body,
    true
  );
  RETURN NULL;
END;
$$;

CREATE TRIGGER broadcast_personal_note_insert
AFTER INSERT ON personal.notes
FOR EACH ROW WHEN (NEW.body LIKE 'swift-private:%')
EXECUTE FUNCTION realtime_test.broadcast_personal_note_insert();

-- `postgresChanges(select:)` reads changes on `personal.notes`, so the Realtime tests that watch
-- `key_value_storage` never see these rows.
ALTER PUBLICATION supabase_realtime ADD TABLE personal.notes;
