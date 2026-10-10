-- One column per Postgres type that supabase-typegen maps to a dedicated Swift type or to a
-- plain `String`, for PostgresValuesIntegrationTests.
CREATE TYPE money_pair AS (amount INTEGER, currency TEXT);

CREATE TABLE postgres_values (
  id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  int_span INT4RANGE,
  big_span INT8RANGE,
  num_span NUMRANGE,
  local_span TSRANGE,
  instant_span TSTZRANGE,
  day_span DATERANGE,
  duration INTERVAL,
  at_time TIME,
  at_time_tz TIMETZ,
  payload BYTEA,
  address INET,
  network CIDR,
  mac MACADDR,
  price MONEY,
  document XML,
  pair MONEY_PAIR,
  spot POINT
);

GRANT ALL ON TABLE public.postgres_values TO anon, authenticated;
