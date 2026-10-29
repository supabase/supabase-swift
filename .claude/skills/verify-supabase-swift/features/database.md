# Database

An app reads and writes Postgres tables through PostgREST with `client.from(_:)`, and calls
Postgres functions with `client.rpc(_:params:)`. Results decode into the app's `Decodable` types.

## Sub-features

- `db-read-seed` selects rows with a column list and an order.
- `db-insert` inserts a row and returns it with `returning: .representation` and `.single()`.
- `db-filter` filters rows with `.eq`.
- `db-update` updates a row by id and returns the new row.
- `db-delete` deletes a row by id; a later select finds nothing.
- `db-rpc` calls a SQL function and decodes a scalar result.

## How to get to it (user POV)

- `client.from("todos").select(...).eq(...).order(...).execute().value`
- `client.from("todos").insert(_:returning:)`, `.update(_:returning:)`, `.delete()`
- `client.rpc("get_status", params: [...]).execute().value`
- Typed API with `@Table` structs is not in the bundled journey. See Gotchas.

## Driving it with verify.sh

Preconditions:

- A run from `$V up` is live and `$V doctor` is all `ok`.
- The seeded `users` table holds exactly four rows.

- **Read.** Select usernames ordered by name. Run `$V drive database`. Step `db-read-seed`
  passes with `["awailas", "dragarcia", "kiwicopple", "supabot"]` and saves
  `db-read-seed.json`.
- **Insert.** The journey inserts `todo-<run-id>-<hex>`. Step `db-insert` passes and saves
  the returned row to `db-insert.json` with `is_complete` false.
- **Filter.** Step `db-filter` finds exactly that row by description.
- **Update.** Step `db-update` sets `is_complete` true and saves `db-update.json`.
- **RPC.** Step `db-rpc` returns `ONLINE` for `supabot`.
- **Delete.** Step `db-delete` inserts a `doomed-...` row, deletes it, and finds zero rows.
- **Outside view.** Run
  `$V sql "select id, description, is_complete, tags from public.todos where description like 'todo-$VERIFY_RUN_ID-%'"`.
  The row from `db-insert` shows `is_complete: true` and `tags: ["verify"]`. Save the output in
  the evidence folder as `db-row.sql.json`.

## Gotchas

- The journey's `todos` row stays after the run on purpose, so `sql` can show it. A rerun adds
  a new row with a new suffix. Count by the run id prefix, not the whole table.
- `PostgrestIntegrationTests` deletes every `todos` row in its `init`. Do not point the
  integration tests at a verification stack.
- PostgREST returns `uuid` values in lower case, and Swift's `UUID` prints upper case. Compare
  `UUID` values, not strings.
- The `@Table` macros and the typed API (`features=typed-api` in `X-Client-Info`) need
  generated types. To verify them, add a journey with `@Table` structs that match the
  migrations in `Tests/IntegrationTests/supabase/migrations/`.
