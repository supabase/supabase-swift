# Development

How to build, test, lint, and run supabase-swift locally.

## Requirements

- Xcode 26.0+ (supports versions eligible for App Store submission)
- Swift 6.2+
- Supported platforms: iOS 16.0+, macOS 13.0+, tvOS 16+, watchOS 9+, visionOS 1+
- Linux is supported for building but not officially supported for production use

## Build Commands

```bash
# Build the package
swift build

# Build for specific configuration
swift build -c debug
swift build -c release

# Build with library evolution
./scripts/build-for-library-evolution.sh

# Build using Xcode
PLATFORM=IOS ./scripts/xcodebuild.sh
PLATFORM=MACOS ./scripts/xcodebuild.sh
```

## Testing Commands

```bash
# Run all tests via Swift Package Manager
swift test

# Run tests for a specific module
swift test --filter AuthTests
swift test --filter StorageTests

# Run tests via Xcode
PLATFORM=IOS XCODEBUILD_ARGUMENT=test ./scripts/xcodebuild.sh

# Run integration tests (requires Supabase instance)
./scripts/test-integration.sh

# Check that Tests/CompileFailures fixtures fail to compile, with the expected error
./scripts/check-compile-failures.sh

# Generate code coverage
DERIVED_DATA_PATH=~/.derivedData/Debug ./scripts/generate-coverage.sh
```

## Code Formatting

```bash
# Format all Swift files
./scripts/format.sh
```

This uses `swift-format` to automatically format code. All code should be formatted before committing.

Lint rules live in `.swift-format` at the repo root, which enables `NeverUseForceTry` and
`NeverUseImplicitlyUnwrappedOptionals` on top of the defaults. Library code must not trap on a
value a caller supplied — see SDK-1793.

`Tests/.swift-format` turns both back off. Test code has no users to crash: `try!` on a bundled
fixture is the right tool (a missing fixture should fail the run loudly, and a `static let` cannot
be `throws`), and `PostgrestMacrosTests` declares an implicitly unwrapped property on purpose, to
cover how the `@Table` macro handles that spelling.

Check the rules with:

```bash
swift-format lint --recursive --strict Sources Tests tools/supabase-typegen/Sources tools/supabase-typegen/Tests
```

Do not pass `--configuration` — swift-format finds the nearest `.swift-format` per file, and
naming one explicitly applies it everywhere, re-flagging the test code the nested config exempts.

`NeverForceUnwrap` is deliberately **not** enabled. It has no exemption for literals, so it flags
provably-safe constants like `HTTPField.Name("Prefer")!` the same as `dictionary["key"]!` — about
twenty such sites, all of which would need suppressing for no safety gain.

## Spell Checking

Spell-checking uses [cSpell](https://cspell.org), via Node/npm:

```bash
npm ci --prefix tools/node   # one-time setup (re-run only when tools/node/package-lock.json changes)
./scripts/spell-check.sh     # cspell - Swift and Markdown sources
```

Legitimate technical terms and project-specific words go in `dictionary.txt` at the repository root.

## Linting

```bash
# Lint Sources and Tests (fails on any new violation)
swiftlint lint --strict

# Autocorrect violations that SwiftLint can fix
swiftlint lint --fix
```

This uses [SwiftLint](https://github.com/realm/SwiftLint) for code-smell and
correctness rules; `swift-format` remains the source of truth for formatting,
so the SwiftLint config (`.swiftlint.yml`) disables the purely stylistic rules
that overlap with it. Install SwiftLint locally with `brew install swiftlint`.

## Documentation

```bash
# Test documentation build
./scripts/test-docs.sh
```

Ensures DocC documentation builds without warnings.

## Running a Local Supabase Stack

On macOS, always start local Supabase with the CLI's experimental native stack. It runs every
service as a native process, with no Docker, so it starts much faster. CI's macOS integration job
uses the same stack, so a local run matches CI. Use it for local development, the integration
tests, and the `Examples` app:

```bash
export SUPABASE_EXPERIMENTAL_STACK=1
supabase start --runtime native
```

- `supabase start` applies the migrations and the seed. You do not need `supabase db reset`
  after it.
- An older Docker stack (one started without `SUPABASE_EXPERIMENTAL_STACK`) holds the same
  ports, so the native stack fails with "Public port 54322 ... is already in use". Stop the
  Docker stack with the variable unset, from the directory that started it:

  ```bash
  env -u SUPABASE_EXPERIMENTAL_STACK supabase stop
  ```
- Linux has no native stack. There, run plain `supabase start`, which uses Docker.

## Working with Integration Tests

Integration tests require a local Supabase instance (see "Running a Local Supabase Stack"). The
`swift test` flags below match CI's macOS job: swift-snapshot-testing needs Swift Testing's
cross-import overlays, which SwiftPM does not turn on by itself, and those overlays need
macOS 14. `--eager` starts every service before `start` returns, as CI does. On Linux, drop the
experimental-stack variable and every flag, but keep `INTEGRATION_TESTS`:

```bash
export INTEGRATION_TESTS=1  # the suites skip themselves without it
export SUPABASE_EXPERIMENTAL_STACK=1
SWIFT_FLAGS="--triple arm64-apple-macosx14.0 -Xswiftc -Xfrontend -Xswiftc -enable-cross-import-overlays"
cd Tests/IntegrationTests
supabase start --runtime native --eager
cd ../..
swift test $SWIFT_FLAGS --filter IntegrationTests --skip verifyOTPForSecureEmailChange --no-parallel
cd Tests/IntegrationTests
supabase stop
```

`./scripts/test-integration.sh` runs these steps for you.

The CLI starts Storage without object lifecycles, analytics (Iceberg) buckets or a CDN purge
endpoint, and has no setting for them. On the Docker stack (Linux, and CI's Linux job),
`./scripts/enable-storage-test-features.sh` recreates the storage container with them on and a stub
that records each CDN purge; then `STORAGE_TEST_FEATURES=1` runs their full integration tests. The
native stack cannot, so without the variable those suites check that Storage refuses each call
instead. To run the full tests on macOS, start the Docker stack (unset
`SUPABASE_EXPERIMENTAL_STACK` and drop `--runtime native --eager`) and run the script after
`supabase start`.

`verifyOTPForSecureEmailChange` needs `auth.email.enable_confirmations = true` to reach GoTrue's
secure-email-change "single confirmation" response, which every other integration test relies on
being `false` (so `signUp`/`signIn` resolve without confirming an email). It runs against a
second, minimal project instead of forking that setting for the whole suite:

```bash
cd Tests/IntegrationTests/supabase-secure-email-change
supabase start --runtime native --eager
cd ../../..
swift test $SWIFT_FLAGS --filter verifyOTPForSecureEmailChange --no-parallel
cd Tests/IntegrationTests/supabase-secure-email-change
supabase stop
```

## CI/CD

### GitHub Actions Workflows

- `ci.yml`: Runs tests on multiple platforms and Xcode versions
- `release.yml`: Automated releases via release-please
- `conventional-commits.yml`: Validates commit message format

### Platform Testing

Tests run on:

- macOS (iOS, macOS, Mac Catalyst, tvOS, watchOS, visionOS simulators)
- Linux (build only, not fully supported)
- Multiple Xcode versions (latest and legacy)

### Code Coverage

Coverage is automatically generated for iOS tests on the main CI job and uploaded to Coveralls.

## Support Policy

- **Xcode**: Only versions eligible for App Store submission
- **Swift**: Minimum version from oldest-supported Xcode
- **Platforms**: Four latest major versions (current + 3 previous)

Dropping support for older versions is NOT considered a breaking change and happens in minor releases.

