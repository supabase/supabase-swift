# supabase-swift verification map

This folder is the maintained source for verifying what supabase-swift does for an app. Read
this index before you drive anything. Then use the matching feature file as the recipe.

The "user" here is an app developer. Their path is a Swift program that imports `Supabase`,
builds a `SupabaseClient`, and calls its public API against a Supabase backend.

## Baseline preconditions

- Start a stack with `$V up` (`V=.claude/skills/verify-supabase-swift/scripts/verify.sh`) and
  export the `VERIFY_RUN_ID` it prints.
- The stack runs the schema, seed, and edge functions from `Tests/IntegrationTests/supabase/`:
  tables `users`, `todos`, `channels`, `messages`, `key_value_storage`, and others; RPCs such as
  `get_status`; functions `echo` and `stream`.
- Seeded users: `awailas`, `dragarcia`, `kiwicopple`, `supabot` (`supabot` is `ONLINE`).
- Email sign-up needs no confirmation. Anonymous sign-in is on.
- `$V doctor` prints only `ok` and `info` lines.
- Never drive a stack that this run did not start. The user's stack on 54321 is off limits.

## Driving conventions

- Every journey is a Swift file in `journeys/` and runs with `$V drive <name>`.
- Journeys call the public API only. No `@testable import`, no `package` symbols.
- Every value a journey creates carries the run id (`Verify.unique`), so reruns on one stack
  do not collide and `sql` can find them by prefix.
- Bound every wait with `Verify.within(seconds:)`.
- To prove a change, copy the closest journey, add the new behavior's steps, and drive the copy.

## Proof and skip reporting

- A proof has the transcript (`stdout.txt` with `STEP`/`PASS`/`FAIL`/`RESULT`), the saved JSON
  values, and an outside view of each side effect (`$V sql` or `$V http`) in the same
  evidence folder.
- Record which journey and which sub-feature IDs ran. The `meta.json` file records the SDK
  commit and the uncommitted `Sources/` diff.
- A sub-feature that a journey does not cover is unverified. Do not report it as verified
  through a different entry point.
- When a precondition is missing, report `FAIL` with the reason and add it to that feature's
  Gotchas. Do not weaken the check.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph on the behavior an app sees. Then it
has exactly four H2 sections, in this order:

1. `Sub-features` lists short IDs, one line each. The IDs match the journey's step IDs.
2. `How to get to it (user POV)` lists the public API entry points an app calls.
3. `Driving it with verify.sh` starts with `Preconditions:` and pairs each action with the
   journey step and the observable result.
4. `Gotchas` lists traps that waste or invalidate a run.

## Features

- [Database](./database.md) covers PostgREST select, filter, insert, update, delete, and RPC.
- [Auth](./auth.md) covers email sign-up, session, sign-out, sign-in, and auth events.
- [Storage](./storage.md) covers buckets, upload, list, download, signed URLs, and removal.
- [Realtime](./realtime.md) covers broadcast between clients, Postgres change events, presence,
  and channel handles after `removeChannel` or `unsubscribe`.
- [Functions](./functions.md) covers Edge Function invocation with JSON, text, query, region,
  and errors.
