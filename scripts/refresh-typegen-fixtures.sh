#!/usr/bin/env bash
# Regenerates the GeneratorMetadata fixtures in
# tools/supabase-typegen/Tests/SupabaseTypegenTests/Fixtures with
# postgrest-typegen's introspection, from a checkout of supabase/sdk.
#
#   SDK_DIR=~/work/sdk ./scripts/refresh-typegen-fixtures.sh
#
# Needs Docker and bun. Starts two throwaway Postgres containers and removes them on exit:
#   generator_metadata.json         Tests/IntegrationTests/supabase (migrations, then seed.sql)
#   postgrest_typegen_metadata.json postgrest-typegen's test/introspection/fixtures/*.sql
# The two cannot share a database: both define public.users and public.user_status.
set -euo pipefail

: "${SDK_DIR:?Set SDK_DIR to a checkout of https://github.com/supabase/sdk}"
SDK_DIR="$(cd "$SDK_DIR" && pwd)"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE="$SDK_DIR/packages/postgrest-typegen"
FIXTURES="$ROOT/tools/supabase-typegen/Tests/SupabaseTypegenTests/Fixtures"
# The image `supabase start` runs for Tests/IntegrationTests/supabase (major_version 15). It
# carries the auth schema and the roles the migrations grant to.
SUPABASE_IMAGE="${SUPABASE_IMAGE:-public.ecr.aws/supabase/postgres:15.19.0.004}"
# The image postgrest-typegen's own introspection tests use.
POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgres:15-alpine}"

(cd "$PACKAGE" && bun install --frozen-lockfile >/dev/null)

CONTAINERS=()
trap 'if ((${#CONTAINERS[@]})); then docker rm -f "${CONTAINERS[@]}" >/dev/null; fi' EXIT

# Starts a container from $1, applies the SQL files that follow, and writes the metadata to Fixtures/$2.
introspect() {
  local image="$1" out="$2"
  shift 2
  local id
  id="$(docker run -d --quiet -e POSTGRES_PASSWORD=postgres -p 127.0.0.1::5432 "$image")"
  CONTAINERS+=("$id")
  until docker exec "$id" pg_isready -q -h 127.0.0.1 -U postgres; do sleep 1; done
  for file in "$@"; do
    docker exec -i -e PGPASSWORD=postgres "$id" \
      psql -q -v ON_ERROR_STOP=1 -h 127.0.0.1 -U postgres -d postgres <"$file" >/dev/null
  done
  local port
  port="$(docker port "$id" 5432/tcp | head -n1 | sed 's/.*://')"
  bun "$ROOT/scripts/refresh-typegen-fixtures.ts" "$SDK_DIR" \
    "postgres://postgres:postgres@127.0.0.1:$port/postgres" "$FIXTURES/$out"
}

mkdir -p "$FIXTURES"
introspect "$SUPABASE_IMAGE" generator_metadata.json \
  "$ROOT"/Tests/IntegrationTests/supabase/migrations/*.sql \
  "$ROOT/Tests/IntegrationTests/supabase/seed.sql"
introspect "$POSTGRES_IMAGE" postgrest_typegen_metadata.json \
  "$PACKAGE"/test/introspection/fixtures/*.sql

cat >"$FIXTURES/provenance.json" <<EOF
{
  "postgrestTypegenVersion": "$(cd "$PACKAGE" && bun -e 'console.log(require("./package.json").version)')",
  "sdkCommit": "$(git -C "$SDK_DIR" rev-parse HEAD)",
  "generatorMetadataVersion": $(cd "$PACKAGE" && bun -e 'console.log((await import("./src/types.ts")).GENERATOR_METADATA_VERSION)')
}
EOF
echo "Wrote $FIXTURES"
