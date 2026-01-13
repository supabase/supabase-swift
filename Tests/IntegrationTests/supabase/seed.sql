-- Seed data for users table (PostgrestBasicTests)
INSERT INTO users (username, age_range, catchphrase, data, status) VALUES
  ('supabot', '[1,2)', '''cat'' ''fat''', NULL, 'ONLINE'),
  ('kiwicopple', '[25,35)', '''bat'' ''cat''', NULL, 'OFFLINE'),
  ('awailas', '[25,35)', '''bat'' ''rat''', NULL, 'ONLINE'),
  ('dragarcia', '[20,30)', '''fat'' ''rat''', NULL, 'ONLINE');

-- Seed data for channels table
INSERT INTO channels (id, slug) VALUES
  (1, 'public'),
  (2, 'random');

-- Seed data for messages table
INSERT INTO messages (id, channel_id, data, message, username) VALUES
  (1, 1, NULL, 'Hello World 👋', 'supabot'),
  (2, 2, NULL, 'Perfection is attained, not when there is nothing more to add, but when there is nothing left to take away.', 'supabot');

-- Reset sequences to continue from seed data
SELECT setval('channels_id_seq', (SELECT MAX(id) FROM channels));
SELECT setval('messages_id_seq', (SELECT MAX(id) FROM messages));
