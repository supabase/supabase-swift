-- A trigger that broadcasts with `realtime.send`, so a test can receive a message that the
-- database sent, not a client (RealtimeIntegrationTests). The function lives outside `public`,
-- so PostgREST and the typegen fixtures do not see it.
CREATE SCHEMA IF NOT EXISTS realtime_test;

CREATE OR REPLACE FUNCTION realtime_test.broadcast_key_value_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM realtime.send(
    jsonb_build_object('key', NEW.key, 'value', NEW.value),
    'row_inserted',
    NEW.key,
    false
  );
  RETURN NULL;
END;
$$;

CREATE TRIGGER broadcast_key_value_insert
AFTER INSERT ON public.key_value_storage
FOR EACH ROW WHEN (NEW.key LIKE 'trigger-broadcast:%')
EXECUTE FUNCTION realtime_test.broadcast_key_value_insert();
