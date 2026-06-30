-- Seed data for RealtimeV3 integration tests.
-- Kept minimal — most tests create their own rows.

insert into public.messages (room_id, content)
values
  ('00000000-0000-0000-0000-000000000001', 'seed message 1'),
  ('00000000-0000-0000-0000-000000000001', 'seed message 2');
