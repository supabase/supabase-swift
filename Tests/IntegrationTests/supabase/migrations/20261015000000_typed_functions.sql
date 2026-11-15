-- Functions called through `rpc` with typed arguments and results, for
-- PostgrestRpcIntegrationTests: one per kind of result the schema generator handles, an overload
-- pair PostgREST tells apart by argument names, and one it cannot.

CREATE FUNCTION public.search_messages(query text, channel_id integer DEFAULT NULL)
  RETURNS SETOF public.messages
  LANGUAGE sql STABLE
  AS $$
    SELECT * FROM public.messages m
    WHERE m.message ILIKE '%' || query || '%'
      AND (search_messages.channel_id IS NULL OR m.channel_id = search_messages.channel_id)
  $$;

CREATE FUNCTION public.message_by_id(message_id integer) RETURNS public.messages
  LANGUAGE sql STABLE
  AS $$ SELECT * FROM public.messages WHERE id = message_id $$;

CREATE FUNCTION public.channel_message_counts(min_messages integer DEFAULT 0)
  RETURNS TABLE (channel_id integer, slug text, message_count bigint)
  LANGUAGE sql STABLE
  AS $$
    SELECT c.id, c.slug, count(m.id)
    FROM public.channels c LEFT JOIN public.messages m ON m.channel_id = c.id
    GROUP BY c.id, c.slug
    HAVING count(m.id) >= min_messages
  $$;

CREATE FUNCTION public.messages_of(channel_id integer) RETURNS SETOF public.messages
  LANGUAGE sql STABLE
  AS $$ SELECT * FROM public.messages m WHERE m.channel_id = messages_of.channel_id $$;

CREATE FUNCTION public.messages_of(channel_slug text, max_count integer)
  RETURNS SETOF public.messages
  LANGUAGE sql STABLE
  AS $$
    SELECT m.* FROM public.messages m JOIN public.channels c ON c.id = m.channel_id
    WHERE c.slug = channel_slug ORDER BY m.id LIMIT max_count
  $$;

CREATE FUNCTION public.message_ids(statuses public.user_status[]) RETURNS SETOF integer
  LANGUAGE sql STABLE
  AS $$
    SELECT m.id FROM public.messages m JOIN public.users u ON u.username = m.username
    WHERE u.status = ANY (statuses) ORDER BY m.id
  $$;

CREATE FUNCTION public.echo(json) RETURNS json
  LANGUAGE sql IMMUTABLE
  AS $$ SELECT $1 $$;

CREATE FUNCTION public.price_label(amount integer) RETURNS text
  LANGUAGE sql IMMUTABLE
  AS $$ SELECT amount::text $$;

CREATE FUNCTION public.price_label(amount text) RETURNS text
  LANGUAGE sql IMMUTABLE
  AS $$ SELECT amount $$;

GRANT EXECUTE ON FUNCTION public.search_messages(text, integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.message_by_id(integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.channel_message_counts(integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.messages_of(integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.messages_of(text, integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.message_ids(public.user_status[]) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.echo(json) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.price_label(integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.price_label(text) TO anon, authenticated;
