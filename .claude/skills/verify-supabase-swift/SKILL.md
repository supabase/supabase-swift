---
name: verify-supabase-swift
description: Prove a supabase-swift change works the way an app uses it. Starts an isolated local Supabase stack (native runtime, private ports), builds a small Swift program against this checkout's Supabase product, drives Database, Auth, Storage, Realtime, or Functions through the public API, and keeps the transcript and side-effect evidence. Use when asked to verify, demo, or reproduce SDK behavior against a real backend, beyond unit tests.
---

# Verify supabase-swift

supabase-swift is a library. Its user is an app developer who calls `SupabaseClient`. So the
real user path is a Swift program that imports `Supabase` and talks to a real Supabase backend.
This skill gives you that program, a private backend for it, and a place to keep the proof.

All commands run from the repository root. The helper is
`.claude/skills/verify-supabase-swift/scripts/verify.sh`. Below, `V` means that path:

```bash
V=.claude/skills/verify-supabase-swift/scripts/verify.sh
```

Read [features/README.md](features/README.md) before you drive anything. It maps each feature
to its journey and its proof.

## Requirements

- macOS with Swift 6.2+ (Xcode 26). The helper uses the CLI's native stack, which needs no
  Docker. On Linux the helper falls back to the Docker runtime. That path is not verified.
- `supabase` CLI 2.121+ (`brew install supabase/tap/supabase`), `jq`, `curl`, `perl`, `lsof`.
- No `psql` is needed. `$V sql` uses `supabase db query`.

## Launch

```bash
$V up            # or: $V up <run-id>
export VERIFY_RUN_ID=<the id it prints>
```

`up` does this:

1. Copies `Tests/IntegrationTests/supabase/` (config, migrations, seed, edge functions) to
   `.verify/runs/<run-id>/supabase/`.
2. Gives the copy its own `project_id` (`verify-<run-id>`) and a free block of ports
   (`56420-56429`, then `56520-56529`, and so on). The API port is base + 21. The user's own
   stack (54321) and the integration tests are never touched.
3. Runs `supabase start --runtime native --eager` with `SUPABASE_EXPERIMENTAL_STACK=1`. This
   applies every migration and `seed.sql` on an empty database. It takes about 20 s.
4. Writes `.verify/runs/<run-id>/state.env` (URL, keys, port base, stack id, git SHA).
5. Waits until the stack is usable, not only up. It prints
   `ready: rest+seed=200 auth=200 storage=200 functions=200` when the seeded user `supabot`
   is readable over REST, Auth is healthy, Storage answers the service role, and the `echo`
   function answers. If it cannot get there in 180 s, it fails and names the service that is
   not ready.

Teardown is `$V down` (see Cleanup).

## Doctor

Run this first, and again whenever something looks wrong:

```bash
$V doctor
```

It is read-only. Every line must be `ok`:

- `supabase stack status` reports a stack whose `project_root` is this run's folder. This
  proves the stack on these ports is ours, not the user's.
- `lifecycle=running readiness=ready`, and every service is `healthy`.
- The API port is listening. The seed row `supabot` is readable. Auth health and
  `functions/echo` return 200.
- An `info` line gives the SDK commit and how many paths changed under `Sources/`. `drive`
  always builds the working tree as it is now, with your uncommitted changes.

A `FAIL` line means: do not drive this instance. Run `$V down`, then `$V up`.

Do not use `supabase status`. On the native stack, CLI 2.121 hangs on it. Use
`supabase stack status --output-format json` from the run folder.

## Drive

A journey is one `main.swift` that uses only the public API, as an app would:

```bash
$V drive database            # a journey from journeys/<name>.swift
$V drive /path/to/my.swift   # your own journey
$V drive database my-label   # pick the evidence label
```

`drive` does this:

1. Writes `.verify/driver/Package.swift`. This executable package depends on this checkout by
   path, through `.product(name: "Supabase", ...)`.
2. Copies the journey to `main.swift`, and `journeys/Support/Verify.swift` next to it.
3. Runs `swift build`. The first build compiles the SDK and its dependencies (about 1
   minute on an M-series Mac). Later builds are incremental, a few seconds each. A lock
   (`.verify/driver.lock`) makes parallel drives wait their turn.
4. Runs the binary with `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`,
   `SUPABASE_SERVICE_ROLE_KEY`, `VERIFY_RUN_ID`, and `VERIFY_EVIDENCE_DIR` set.
5. Exits with the journey's exit code: `0` all checks passed, `1` a check failed, `2` the build
   failed.

The bundled journeys are `database`, `auth`, `storage`, `realtime`, and `functions`. To prove a
change, copy the closest journey, add steps for the new behavior, and drive your copy. Put
lasting journeys in `journeys/` and list them in the feature map.

### Writing a journey

`Verify.swift` gives every journey:

- `Verify.client()` builds a `SupabaseClient` with the publishable key and an in-memory session
  store. `Verify.client(key: Verify.serviceRoleKey)` builds a server-side client.
- `Verify.unique("prefix")` returns a value with the run id in it, so reruns on one stack do not
  collide.
- `Verify.step(id, detail)` logs the action. `Verify.check(id, condition, detail)` logs
  `PASS`/`FAIL` with the observed value. `Verify.attempt(id) { ... }` turns a thrown error into
  a `FAIL` and goes on.
- `Verify.within(seconds:) { ... }` bounds a wait. Use it for every stream: a missing realtime
  event must fail, not hang.
- `Verify.save("name.json", value)` writes evidence. `Verify.finish()` prints
  `RESULT PASS|FAIL` and exits.

### Looking at side effects from outside the SDK

Check what the SDK wrote with tools that do not use the SDK:

```bash
$V sql "select id, description, is_complete from public.todos where description like 'todo-$VERIFY_RUN_ID-%'"
$V http GET "/auth/v1/admin/users?per_page=50"
$V http GET "/storage/v1/bucket"
```

`sql` prints the result rows as JSON. `http` sends the service role key and prints
`HTTP <code>` and the body. Copy the output you rely on into the evidence folder (see Evidence).

## Evidence

Each drive writes to `.verify/evidence/<run-id>/<label>-<HHMMSS>/`:

| File | Content |
| --- | --- |
| `journey.swift` | The exact program that ran |
| `build.log` | The `swift build` output |
| `stdout.txt`, `stderr.txt` | The transcript: every `STEP`, `PASS`/`FAIL`, `SAVE`, and the `RESULT` line |
| `*.json` | The values the journey saved (rows, sessions, payloads) |
| `exit_code`, `meta.json` | The exit code, SDK commit, uncommitted `Sources/` diff stat, URL, timestamps |

Add the outside view of each side effect to the same folder, for example:

```bash
$V sql "select ..." > "$(ls -d .verify/evidence/$VERIFY_RUN_ID/database-* | tail -1)/db-row.sql.json"
```

Proof standards:

- Drive the public API in a built program. Do not call `package` or `@testable` symbols, and
  do not call internal setters. Unit tests are not proof of user behavior.
- Record the action and the resulting state. A journey logs a `STEP` before each action and a
  `PASS`/`FAIL` with the observed value after it.
- Check each side effect from outside the SDK: the row with `sql`, the user or bucket with
  `http`, the signed URL with a plain `URLSession` GET.
- The stack is real: Postgres, GoTrue, Storage, Realtime, and the Deno edge runtime. Do not
  mock any of them. The only stand-ins are the schema and functions from
  `Tests/IntegrationTests/supabase/`.
- Mail goes to the stack's Mailpit (`SUPABASE_MAILPIT_URL` in `state.env`). No mail leaves the
  machine. Email confirmations are off in this config, so sign-up returns a session at once.
- A journey that cannot reach its precondition reports `FAIL` with the reason. Do not weaken a
  check to make it pass.

## Cleanup

```bash
$V down
```

It does this:

1. Runs `supabase stop` and `supabase stack destroy --yes` from the run folder. This removes
   only this run's stack. It never kills by process name.
2. Deletes `.verify/runs/<run-id>/` (the stack copy, `state.env`, and the built binaries).
3. Fails if the API port still listens.

It keeps `.verify/evidence/<run-id>/` and the shared driver build in `.verify/driver/`.
`.verify/` is in `.gitignore`. Delete old evidence by hand when you no longer need it.

Run `$V down` after a failed `up` too. If `destroy` fails, it prints the command to destroy the
stack by id. Do not stop or destroy stacks this skill did not start. `supabase stack list`
shows many stacks from other worktrees, and they belong to other sessions.

`$V list` shows live runs and the evidence folders.

## Helpers

| Command | Does |
| --- | --- |
| `$V up [run-id]` | Start an isolated stack and wait until it is usable |
| `$V doctor` | Read-only health and ownership check |
| `$V drive <journey\|file.swift> [label]` | Build and run a journey, keep the evidence |
| `$V sql "<query>"` | Run SQL on this run's database, print rows as JSON |
| `$V http <METHOD> </path> [json]` | Call this run's API with the service role key |
| `$V list` | Show live runs and evidence folders |
| `$V down` | Tear down this run's stack, keep the evidence |

Every command except `up` and `list` uses `$VERIFY_RUN_ID`. When it is unset and only one run is
live, they use that run.

## Other surfaces

- `Examples/` holds an iOS app (`Examples.xcodeproj`) with Auth, Database, Storage, Realtime,
  and Functions screens. It reads `Examples/Examples/Supabase.plist` and has its own
  `Examples/supabase/` project. Use it, with the iOS Simulator tools, only when the change is
  about UI integration (for example, OAuth redirects or `ASWebAuthenticationSession`). This
  skill does not cover it.
- `tools/supabase-typegen` is a CLI with its own goldens. See its README.
- `./scripts/test-integration.sh` runs the integration test suites on ports 54321-54329. It is
  a test run, not a user-path proof. It can run at the same time as this skill.
