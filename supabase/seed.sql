-- Seed data for Examples App
-- This file contains sample data for testing the examples

-- Note: In production, you would create users through the auth system
-- For local testing, we can insert some sample data once users are created through the app

-- Sample function to create test data after a user signs up
create or replace function create_sample_data_for_user(user_id uuid)
returns void
language plpgsql
security definer
as $$
begin
  -- Create profile
  insert into profiles (id, username, full_name)
  values (user_id, 'demo_user', 'Demo User')
  on conflict (id) do nothing;

  -- Create sample todos
  insert into todos (description, is_complete, owner_id)
  values
    ('Welcome to Supabase Swift!', false, user_id),
    ('Try creating a new todo', false, user_id),
    ('Mark this todo as complete', false, user_id),
    ('Check out the Storage tab', false, user_id),
    ('Explore Realtime features', false, user_id);

  -- Create sample messages
  insert into messages (content, user_id, channel_id)
  values
    ('Welcome to the Examples app!', user_id, 'general'),
    ('This is a sample message', user_id, 'general');
end;
$$;
