-- A view Postgres cannot update on its own (it groups), made insertable by an INSTEAD OF INSERT
-- trigger. postgrest-typegen reports it as insert-enabled, so supabase-typegen generates it without
-- `readOnly`; PostgrestTriggerWritableViewIntegrationTests inserts through it. It has a table of its
-- own so that test never changes rows another suite counts.

CREATE TABLE public.notes (
  id SERIAL PRIMARY KEY,
  body TEXT NOT NULL
);

CREATE VIEW public.note_summaries AS
SELECT id, body, length(body) AS body_length
FROM public.notes
GROUP BY id;

CREATE FUNCTION public.insert_note_summary() RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  INSERT INTO public.notes (body) VALUES (NEW.body) RETURNING id INTO NEW.id;
  NEW.body_length := length(NEW.body);
  RETURN NEW;
END;
$$;

CREATE TRIGGER insert_note_summary
  INSTEAD OF INSERT ON public.note_summaries
  FOR EACH ROW EXECUTE FUNCTION public.insert_note_summary();

GRANT ALL ON TABLE public.notes TO anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.notes_id_seq TO anon, authenticated;
GRANT SELECT, INSERT ON public.note_summaries TO anon, authenticated;
