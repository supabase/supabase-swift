// Introspects one database with postgrest-typegen and writes the sorted GeneratorMetadata
// document, as `supabase gen types` sends it to an external generator.
// Run by refresh-typegen-fixtures.sh: bun refresh-typegen-fixtures.ts <sdk-dir> <database-url> <output>
import { createRequire } from "node:module";
import { writeFileSync } from "node:fs";

const [sdkDir, databaseURL, output] = process.argv.slice(2);
const packageDir = `${sdkDir}/packages/postgrest-typegen`;
const { introspect, serializeGeneratorMetadata, sortGeneratorMetadata } = await import(
  `${packageDir}/src/index.ts`
);
const { Pool } = createRequire(`${packageDir}/package.json`)("pg");

// The Supabase CLI's internal schemas (`utils.InternalSchemas`), left out of `gen types` when no
// --schema is given.
const internalSchemas = [
  "information_schema", "pg_%", "_analytics", "_realtime", "_supavisor", "auth", "extensions",
  "pgbouncer", "realtime", "storage", "supabase_functions", "supabase_migrations", "cron", "dbdev",
  "graphql", "graphql_public", "net", "pgmq", "pgsodium", "pgsodium_masks", "pgtle", "repack",
  "tiger", "tiger_data", "timescaledb_%", "_timescaledb_%", "topology", "vault",
];

const pool = new Pool({ connectionString: databaseURL });
try {
  const { rows } = await pool.query(
    "select nspname from pg_namespace where not nspname like any($1) order by nspname",
    [internalSchemas],
  );
  const metadata = await introspect(pool, { includedSchemas: rows.map((row) => row.nspname) });
  const json = JSON.stringify(JSON.parse(serializeGeneratorMetadata(sortGeneratorMetadata(metadata))), null, 2);
  writeFileSync(output, `${json}\n`);
} finally {
  await pool.end();
}
