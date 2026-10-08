-- Computed members of `channels`, for PostgrestComputedMemberIntegrationTests. PostgREST exposes a
-- function whose only argument is a relation's row type as part of that relation: a scalar one as a
-- computed field, a row- or set-returning one as a computed relationship. Neither is in `select=*`.

CREATE FUNCTION public.shouted_slug(public.channels) RETURNS text
  LANGUAGE sql STABLE
  AS $$ SELECT upper($1.slug) $$;

CREATE FUNCTION public.channel_messages(public.channels) RETURNS SETOF public.messages
  LANGUAGE sql STABLE
  AS $$ SELECT * FROM public.messages WHERE channel_id = $1.id $$;

CREATE FUNCTION public.first_message(public.channels) RETURNS public.messages
  LANGUAGE sql STABLE
  AS $$ SELECT * FROM public.messages WHERE channel_id = $1.id ORDER BY id LIMIT 1 $$;

GRANT EXECUTE ON FUNCTION public.shouted_slug(public.channels) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.channel_messages(public.channels) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.first_message(public.channels) TO anon, authenticated;
