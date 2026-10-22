-- A table with a GENERATED ALWAYS identity key and a GENERATED ALWAYS … STORED column, for
-- PostgrestGeneratedColumnIntegrationTests: Postgres answers 428C9 to any write naming either.
CREATE TABLE counters (
  id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  count INTEGER NOT NULL,
  doubled INTEGER GENERATED ALWAYS AS (count * 2) STORED
);

GRANT ALL ON TABLE public.counters TO anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.counters_id_seq TO anon, authenticated;
