# Remove the Makefile

## Context

`supabase-go`'s `decisions.md` records a convention: no `Makefile` or task
runner — CI and local dev use plain toolchain commands only, because a
`Makefile` is a borrowed-from-C convention that only earns its place when a
repo orchestrates non-language work (docker, migrations, codegen,
cross-compile, release packaging). A pure Go library has none of that.

`supabase-swift`'s `Makefile` *does* orchestrate real non-trivial work:
simulator selection/boot for `xcodebuild`, DocC warning filtering, coverage
export, an npm-based spell checker, and a Supabase CLI integration-test
lifecycle. Adapting the Go SDK's rule here means: stop using `make` as the
indirection layer, but keep the orchestration logic that genuinely needs it —
as plain, directly-invocable scripts under `scripts/`, matching the two
scripts (`generate-coverage.sh`, `spell-check.sh`) that already exist there
and are already called directly by CI in some places.

## Goal

Delete the `Makefile`. Every current `make <target>` invocation (in CI,
`AGENTS.md`, `README.md`) is replaced with either a direct toolchain command
or a direct script invocation — never routed through `make`.

## Non-goals

- No behavior changes. Every script preserves the current Make recipe's
  behavior exactly, including existing quirks (e.g. `warm-simulator`'s silent
  no-op when the destination has no simulator id — macOS/Mac Catalyst boot
  attempts fail harmlessly today, and that stays true).
- No new error handling, retries, or cleanup logic beyond what the Makefile
  already does (e.g. `test-integration` still won't run `supabase stop` if
  `swift test` fails, matching today's Make recipe behavior of one subshell
  per recipe line).
- Not touching the `integration-tests` CI job on Linux — it already inlines
  the Supabase CLI lifecycle itself and never called `make test-integration`.

## Design

### Target disposition

Every Makefile target becomes a `scripts/*.sh` file, called directly (no
`make`). This keeps a single source of truth for anything referenced from
more than one place (CI, `AGENTS.md`, `README.md`) instead of copy-pasting
shell one-liners three times.

| Makefile target | Becomes |
|---|---|
| `xcodebuild` + `warm-simulator` + `udid_for` | `scripts/xcodebuild.sh` |
| `test-docs` | `scripts/test-docs.sh` |
| `test-integration` | `scripts/test-integration.sh` |
| `build-for-library-evolution` | `scripts/build-for-library-evolution.sh` |
| `format` | `scripts/format.sh` |
| `coverage` | unchanged — already `scripts/generate-coverage.sh`; call it directly |
| `spell-check` | unchanged — already `scripts/spell-check.sh`; call it directly |

### `scripts/xcodebuild.sh`

Reads the same env vars as today's Make variables, with the same defaults:

- `PLATFORM` (default `IOS`) — one of `IOS`, `MACOS`, `MAC_CATALYST`,
  `TVOS`, `VISIONOS`, `WATCHOS`
- `CONFIG` (default `Debug`)
- `SCHEME` (default `Supabase`)
- `WORKSPACE` (default `Supabase.xcworkspace`)
- `XCODEBUILD_ARGUMENT` (default `test`)
- `DERIVED_DATA_PATH` (default `~/.derivedData/$CONFIG`)

Behavior, ported faithfully from the Makefile:

1. Map `PLATFORM` to a `-destination` string. For `IOS`/`TVOS`/`VISIONOS`/
   `WATCHOS` this requires a simulator UDID, found via the same
   `simctl list --json devices available <name> | jq '...'` query as the
   current `udid_for` macro (including its existing quirk: the second
   argument in `PLATFORM_IOS = ...,id=$(call udid_for,iOS,iPhone \d\+ Pro
   [^M])` is unused today and won't be ported in — `udid_for` only ever
   consulted its first argument).
2. Extract a simulator id from the destination string via the same
   `sed -E "s/.+,id=(.+)/\1/"` substitution used today, and attempt
   `xcrun simctl boot <id> && open -a Simulator --args -CurrentDeviceUDID
   <id>`, swallowing any failure — this reproduces today's behavior where
   `MACOS`/`MAC_CATALYST` destinations (no id) cause a harmless failed boot
   attempt that's silently ignored.
3. Run `xcodebuild $XCODEBUILD_ARGUMENT` with the same flags
   (`-configuration`, `-derivedDataPath`, `-destination`, `-scheme`,
   `-skipMacroValidation`, `-workspace`), piping through `xcbeautify` when
   it's on `PATH`, matching today's conditional.

### `scripts/test-docs.sh`

Runs `xcodebuild clean docbuild -scheme Supabase -destination
'platform=macOS' -quiet`, filters stderr/stdout for `"couldn't be resolved to
known documentation"` lines (path-normalized the same way, via
`sed "s|$PWD|.|g"`), and exits 1 printing the warnings if any are found —
otherwise exits 0. Same behavior as today's `DOC_WARNINGS`/`test-docs`
Make recipe pair, just without the `tr '\n' '\1'` null-byte trick Make
needed to hold a multi-line value in a variable.

### `scripts/test-integration.sh`

```
cd Tests/IntegrationTests && supabase start && supabase db reset
cd ../.. && swift test --filter IntegrationTests
cd Tests/IntegrationTests && supabase stop
```

Same three-step structure as today's three separate Make recipe lines,
including the existing behavior that a failing `swift test` skips `supabase
stop` (no new cleanup/trap logic is being added).

### `scripts/build-for-library-evolution.sh` and `scripts/format.sh`

Each is a one-line wrapper around today's exact Make recipe command
(`swift build -q -c release --target Supabase -Xswiftc
-emit-module-interface -Xswiftc -enable-library-evolution`, and the
`find ... -name '*.swift' ... | xargs -0 xcrun swift-format ...` pipeline,
respectively). No behavior change — this just gives them a single, stable
call site instead of being duplicated across `AGENTS.md`, `README.md`, and
`ci.yml`.

### CI (`.github/workflows/ci.yml`) changes

Every `make ...` step becomes a direct script call with the same env vars
passed as shell environment instead of Make variable overrides:

- `macos`/`macos-legacy` Debug/Release steps →
  `CONFIG=... PLATFORM=... XCODEBUILD_ARGUMENT=... ./scripts/xcodebuild.sh`
- `macos` coverage step →
  `DERIVED_DATA_PATH=~/.derivedData/Debug ./scripts/generate-coverage.sh`
  (explicit path, since this step no longer shares Make's variable
  derivation with the preceding xcodebuild step)
- `library-evolution` step → `./scripts/build-for-library-evolution.sh`
- `examples` step →
  `DERIVED_DATA_PATH=~/.derivedData SCHEME=... XCODEBUILD_ARGUMENT=build ./scripts/xcodebuild.sh`
- `docs` step → `./scripts/test-docs.sh`
- `format-check` job's failure message stops saying `Run 'make format'
  locally` and instead points at `./scripts/format.sh`

### Documentation changes

- `AGENTS.md`: Build/Testing Commands sections rewritten to reference the
  scripts directly (e.g. `./scripts/xcodebuild.sh` with env vars documented
  the same way `make PLATFORM=... xcodebuild` is today); "Important Notes"
  section's "Always run `make format`" becomes "Always run
  `./scripts/format.sh`".
- `README.md`: Contributing steps 4–5 updated to
  `./scripts/format.sh` and `PLATFORM=IOS XCODEBUILD_ARGUMENT=test
  ./scripts/xcodebuild.sh`.

## Testing / verification plan

- Make all new scripts executable (`chmod +x`) and shellcheck-clean by eye
  (no shellcheck tool assumed installed).
- Run locally, comparing against current `make` output for the same
  invocation where feasible:
  - `./scripts/xcodebuild.sh` (default `PLATFORM=IOS XCODEBUILD_ARGUMENT=test`)
  - `PLATFORM=MACOS ./scripts/xcodebuild.sh` (verify harmless boot no-op)
  - `./scripts/test-docs.sh`
  - `./scripts/format.sh` (verify identical diff to `make format` on a
    scratch change)
  - `./scripts/build-for-library-evolution.sh`
- `./scripts/test-integration.sh` — structural review only unless a local
  Supabase instance is available to run it end-to-end.
- Confirm `git diff` shows the Makefile fully removed and no remaining
  `make ` references in `.github/workflows/ci.yml`, `AGENTS.md`, or
  `README.md` (`grep -rn 'make ' --include=*.md --include=*.yml`).
