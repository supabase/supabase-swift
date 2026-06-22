-- Grant API access to tables for anon and authenticated roles.
-- Required since Supabase no longer grants public schema access by default
-- (see https://github.com/orgs/supabase/discussions/45329).
GRANT ALL ON TABLE public.users TO anon, authenticated;
GRANT ALL ON TABLE public.todos TO anon, authenticated;
GRANT ALL ON TABLE public.messages TO anon, authenticated;
GRANT ALL ON TABLE public.channels TO anon, authenticated;
GRANT ALL ON TABLE public.key_value_storage TO anon, authenticated;

-- Grant SELECT on updatable view
GRANT SELECT ON public.updatable_view TO anon, authenticated;

-- Grant sequence usage for SERIAL primary key columns
GRANT USAGE, SELECT ON SEQUENCE public.channels_id_seq TO anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.messages_id_seq TO anon, authenticated;

-- Grant EXECUTE on RPC functions
GRANT EXECUTE ON FUNCTION public.get_status(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.void_func() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_user() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_username_and_status(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_array_element(INT[], INT) TO anon, authenticated;
