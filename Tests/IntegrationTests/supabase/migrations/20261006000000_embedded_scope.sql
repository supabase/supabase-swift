-- Discussions, posts and replies, for PostgrestEmbeddedScopeIntegrationTests.
--
-- discussions and posts are joined by two foreign keys (posts.discussion_id and
-- discussions.pinned_post_id), so an embed between them with no foreign-key hint is ambiguous
-- and PostgREST answers HTTP 300 PGRST201. A @Relationship always carries the hint.
CREATE TABLE discussions (
  id SERIAL PRIMARY KEY,
  title TEXT NOT NULL
);

CREATE TABLE posts (
  id SERIAL PRIMARY KEY,
  discussion_id INTEGER NOT NULL REFERENCES discussions(id),
  author TEXT NOT NULL,
  approved BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

ALTER TABLE discussions ADD COLUMN pinned_post_id INTEGER REFERENCES posts(id);

CREATE TABLE replies (
  id SERIAL PRIMARY KEY,
  post_id INTEGER NOT NULL REFERENCES posts(id),
  body TEXT NOT NULL,
  approved BOOLEAN NOT NULL DEFAULT false
);

ALTER TABLE discussions ENABLE ROW LEVEL SECURITY;
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE replies ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow all operations on discussions" ON discussions FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations on posts" ON posts FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations on replies" ON replies FOR ALL USING (true) WITH CHECK (true);

GRANT ALL ON TABLE public.discussions TO anon, authenticated;
GRANT ALL ON TABLE public.posts TO anon, authenticated;
GRANT ALL ON TABLE public.replies TO anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.discussions_id_seq TO anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.posts_id_seq TO anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.replies_id_seq TO anon, authenticated;
