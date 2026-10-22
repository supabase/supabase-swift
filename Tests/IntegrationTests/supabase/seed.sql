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

-- Seed data for the embedded-scope tables (PostgrestEmbeddedScopeIntegrationTests). Read-only
-- fixtures: discussion 3 has no posts, discussion 4 has only an unapproved one.
INSERT INTO discussions (id, title) VALUES
  (1, 'swift'),
  (2, 'rust'),
  (3, 'empty'),
  (4, 'unapproved');

INSERT INTO posts (id, discussion_id, author, approved, created_at) VALUES
  (1, 1, 'ada', true,  '2026-01-01T00:00:00Z'),
  (2, 1, 'bob', false, '2026-01-02T00:00:00Z'),
  (3, 1, 'ada', true,  '2026-01-03T00:00:00Z'),
  (4, 2, 'cy',  true,  '2026-01-04T00:00:00Z'),
  (5, 4, 'bob', false, '2026-01-05T00:00:00Z');

UPDATE discussions SET pinned_post_id = 3 WHERE id = 1;

INSERT INTO replies (id, post_id, body, approved) VALUES
  (1, 1, 'nice', true),
  (2, 1, 'spam', false),
  (3, 1, 'ok',   true),
  (4, 4, 'hm',   false);

SELECT setval('discussions_id_seq', (SELECT MAX(id) FROM discussions));
SELECT setval('posts_id_seq', (SELECT MAX(id) FROM posts));
SELECT setval('replies_id_seq', (SELECT MAX(id) FROM replies));
