-- Realtime v3 integration tests: a table for postgres_changes, and broadcast/presence policies for
-- private channels.

CREATE TABLE public.realtime_items (
  id bigserial PRIMARY KEY,
  list_id int NOT NULL,
  title text NOT NULL
);

-- Old rows carry every column on update and delete, not only the primary key.
ALTER TABLE public.realtime_items REPLICA IDENTITY FULL;

ALTER TABLE public.realtime_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations on realtime_items" ON public.realtime_items
  FOR ALL USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.realtime_items TO anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.realtime_items_id_seq TO anon, authenticated;

ALTER PUBLICATION supabase_realtime ADD TABLE public.realtime_items;

-- Private channels: only signed-in users, and only on topics starting with `private-`.
CREATE POLICY "Authenticated users read private topics" ON realtime.messages
  FOR SELECT TO authenticated
  USING (realtime.topic() LIKE 'private-%');

CREATE POLICY "Authenticated users write private topics" ON realtime.messages
  FOR INSERT TO authenticated
  WITH CHECK (realtime.topic() LIKE 'private-%');
