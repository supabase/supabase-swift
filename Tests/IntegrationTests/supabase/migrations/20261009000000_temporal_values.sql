-- One column per Postgres date/time type that supabase-typegen maps to `Date`, for
-- PostgrestTemporalRoundTripIntegrationTests.
CREATE TABLE temporal_values (
  id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  at_instant TIMESTAMP WITH TIME ZONE NOT NULL,
  at_local TIMESTAMP WITHOUT TIME ZONE NOT NULL,
  on_day DATE NOT NULL
);

GRANT ALL ON TABLE public.temporal_values TO anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.temporal_values_id_seq TO anon, authenticated;
