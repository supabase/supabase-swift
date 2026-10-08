-- A deliberately slow RPC, so a test can cancel a request that is genuinely in flight
-- (PostgrestCancellationIntegrationTests).
CREATE OR REPLACE FUNCTION public.sleep_for(seconds double precision)
RETURNS void AS $$
  SELECT pg_sleep(seconds);
$$ LANGUAGE sql;

GRANT EXECUTE ON FUNCTION public.sleep_for(double precision) TO anon, authenticated;
