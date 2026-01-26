-- Create custom types
CREATE TYPE user_status AS ENUM ('ONLINE', 'OFFLINE');

-- Users table (supports both PostgrestIntegrationTests and PostgrestBasicTests)
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT,
  username TEXT UNIQUE,
  age_range int4range,
  catchphrase TEXT,
  data JSONB,
  status user_status DEFAULT 'ONLINE'
);

-- Todos table
CREATE TABLE todos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  description TEXT NOT NULL,
  is_complete BOOLEAN NOT NULL DEFAULT false,
  tags TEXT[] DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Channels table
CREATE TABLE channels (
  id SERIAL PRIMARY KEY,
  slug TEXT NOT NULL
);

-- Messages table
CREATE TABLE messages (
  id SERIAL PRIMARY KEY,
  channel_id INTEGER REFERENCES channels(id),
  data JSONB,
  message TEXT,
  username TEXT REFERENCES users(username)
);

-- Key-value storage table for Realtime tests
CREATE TABLE key_value_storage (
  key TEXT PRIMARY KEY,
  value JSONB
);

-- Create updatable view (for PostgrestBasicTests)
CREATE VIEW updatable_view AS
SELECT username, 1 AS non_updatable_column
FROM users
WHERE username IS NOT NULL;

-- RPC function to get status
CREATE OR REPLACE FUNCTION get_status(name_param TEXT)
RETURNS TEXT AS $$
BEGIN
  RETURN (SELECT status::TEXT FROM users WHERE username = name_param);
END;
$$ LANGUAGE plpgsql;

-- RPC function that returns void
CREATE OR REPLACE FUNCTION void_func()
RETURNS VOID AS $$
BEGIN
  -- Does nothing
END;
$$ LANGUAGE plpgsql;

-- RPC function to delete current user (for AuthClientIntegrationTests)
CREATE OR REPLACE FUNCTION delete_user()
RETURNS VOID AS $$
BEGIN
  DELETE FROM auth.users WHERE id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC function to get username and status (for PostgrestFilterTests)
CREATE OR REPLACE FUNCTION get_username_and_status(name_param TEXT)
RETURNS TABLE(username TEXT, status user_status) AS $$
BEGIN
  RETURN QUERY SELECT u.username, u.status FROM users u WHERE u.username = name_param;
END;
$$ LANGUAGE plpgsql;

-- RPC function to get array element (for PostgrestTransformsTests)
CREATE OR REPLACE FUNCTION get_array_element(arr INT[], index INT)
RETURNS INT AS $$
BEGIN
  RETURN arr[index];
END;
$$ LANGUAGE plpgsql;

-- Enable Row Level Security
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE todos ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE key_value_storage ENABLE ROW LEVEL SECURITY;

-- Create permissive policies for testing (allow all operations)
CREATE POLICY "Allow all operations on users" ON users FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations on todos" ON todos FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations on messages" ON messages FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations on channels" ON channels FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations on key_value_storage" ON key_value_storage FOR ALL USING (true) WITH CHECK (true);

-- Enable realtime for key_value_storage table
ALTER PUBLICATION supabase_realtime ADD TABLE key_value_storage;
