# Instructions for supabase-swift

## Repository Overview

This is the official Supabase SDK for Swift (version **2.48.0**), mirroring the design of supabase-js. It provides a Swift client for interacting with Supabase services including Auth, Database (PostgREST), Realtime, Storage, and Functions.

## Project Structure

```
Sources/
├── Supabase/          # Main client (SupabaseClient facade)
├── Auth/              # Authentication (email, OAuth, magic link, OTP, MFA, WebAuthn)
│   ├── Internal/      # APIClient, Keychain, JWT+RSA, URLOpener, etc.
│   ├── Storage/       # Keychain, WinCred, AuthLocalStorage backends
│   └── WebAuthn/      # Passkey support (@_spi(Experimental))
├── PostgREST/         # Database query builder
├── Realtime/          # WebSocket subscriptions (V2 API; Deprecated/ contains legacy)
├── Storage/           # File/bucket management
├── Functions/         # Edge Functions invocation
├── Helpers/           # Shared HTTP layer, AnyJSON, logging, JWT utilities
│   ├── HTTP/          # HTTPClient, interceptors (retry, logging)
│   ├── Logger/        # SupabaseLogger, OSLogSupabaseLogger
│   └── AnyJSON/       # Dynamic JSON representation
└── TestHelpers/       # Shared test utilities (production target, import in tests)

Tests/
├── AuthTests/
├── PostgRESTTests/
├── RealtimeTests/
├── StorageTests/
├── FunctionsTests/
├── HelpersTests/
├── SupabaseTests/
└── IntegrationTests/  # Requires live Supabase instance

Examples/
├── Examples/          # Comprehensive feature demo (Auth, DB, Realtime, Storage, Functions)
├── SlackClone/        # Full-featured Slack-like app
└── UserManagement/    # Auth + profile management
```

## Development Environment

### Requirements

- Xcode 15.3+ (only versions eligible for App Store submission)
- Swift 5.10+
- Supported platforms (from Package.swift): iOS 13.0+, macCatalyst 13.0+, macOS 10.15+, watchOS 6.0+, tvOS 13.0+
- visionOS is supported via conditional compilation but not listed in Package.swift platforms
- Linux: supported for building and unit tests; not officially supported for production

### Build Commands

```bash
# Build via SPM
swift build
swift build -c debug
swift build -c release

# Build with library evolution (ABI stability check)
make build-for-library-evolution

# Build via Xcode (PLATFORM: IOS | MACOS | MAC_CATALYST | TVOS | WATCHOS | VISIONOS)
make PLATFORM=IOS xcodebuild
make PLATFORM=MACOS xcodebuild
make PLATFORM=IOS CONFIG=Release xcodebuild
```

### Testing Commands

```bash
# Run all unit tests via SPM
swift test

# Run tests for a specific module
swift test --filter AuthTests
swift test --filter StorageTests

# Run tests via Xcode (sets up simulator first)
make PLATFORM=IOS XCODEBUILD_ARGUMENT=test xcodebuild

# Run integration tests (requires Supabase CLI)
make test-integration

# Generate code coverage report
make coverage
```

### Code Formatting

```bash
# Format all Swift files (MUST run before committing)
make format
```

Uses `swift-format` (via `xcrun swift-format`). The CI `format-check` job validates formatting on PRs. All code must be formatted before committing.

### Documentation

```bash
# Verify DocC documentation builds without warnings
make test-docs
```

## Code Style and Conventions

### Swift Style

- 2-space indentation (configured in `.editorconfig`)
- Upcoming feature enabled: `ExistentialAny` (use `any Protocol` explicitly)
- Experimental feature enabled: `StrictConcurrency` (Swift 6 strict concurrency)
- These apply to all non-test targets via `Package.swift` loop at bottom
- Prefer `async/await` over completion handlers
- Mark types as `Sendable` where appropriate

### File Headers

```swift
//
//  FileName.swift
//  ModuleName
//
//  Created by Author Name on DD/MM/YY.
//
```

### Module Organization

- Each module is independent and can be used standalone
- `Sources/Supabase/Exports.swift` re-exports all sub-modules with `@_exported import`
- Some experimental APIs are gated with `@_spi(Experimental)` (e.g., WebAuthn in Auth)
- Keep module dependencies minimal; follow the dependency graph in `Package.swift`

### Error Handling

- Use strongly-typed errors conforming to `Error` and `LocalizedError`
- Use `async throws` for async error handling
- Report unexpected states with `IssueReporting` from `xctest-dynamic-overlay`

### Concurrency

- `AuthClient` is an `actor`
- `FunctionsClient` is an `actor`
- `SupabaseClient`, `PostgrestClient`, `RealtimeClientV2` are `final class` with `Sendable`
- Mutable state in `Sendable` classes uses `LockIsolated` from `ConcurrencyExtras`
- All new async code must handle task cancellation

### Realtime V2 vs Deprecated

`RealtimeClientV2` and `RealtimeChannelV2` are the current API. The `Realtime/Deprecated/` directory contains the old `RealtimeChannel` and `PhoenixTransport` — do not use these in new code.

### Testing Conventions

- Mirror source structure: `Foo.swift` → `FooTests.swift`
- Use `@testable import` for internal access
- Snapshot tests use both `SnapshotTesting` and `InlineSnapshotTesting`; reference files live in `__Snapshots__/` (excluded from SPM target, committed to repo)
- Use `Mocker` for URLSession HTTP mocking
- Use `CustomDump` for richer assertion output
- Integration tests require `INTEGRATION_TESTS=1` env var (set automatically by CI)

```swift
import XCTest
@testable import ModuleName

final class FeatureTests: XCTestCase {
  func testFeatureBehavior() async throws {
    // Arrange
    let sut = makeSUT()

    // Act
    let result = try await sut.doThing()

    // Assert
    XCTAssertEqual(result, expected)
  }
}
```

## Package.swift Targets and Dependencies

### Products (6 libraries)

| Product | Target | Description |
|---------|--------|-------------|
| `Supabase` | Supabase | Full client (includes all below) |
| `Auth` | Auth | Authentication/session management |
| `PostgREST` | PostgREST | Database query builder |
| `Realtime` | Realtime | WebSocket subscriptions |
| `Storage` | Storage | File/bucket management |
| `Functions` | Functions | Edge Functions invocation |

### Dependencies (exact versions from Package.swift)

| Package | Version | Used By |
|---------|---------|---------|
| `apple/swift-crypto` | `"3.0.0"..<"5.0.0"` | Auth (PKCE, JWT, WebAuthn) |
| `apple/swift-http-types` | `from: "1.3.0"` | Helpers, Auth, PostgREST, Realtime, Storage, Functions |
| `pointfreeco/swift-clocks` | `from: "1.0.0"` | Helpers |
| `pointfreeco/swift-concurrency-extras` | `from: "1.1.0"` | All production targets |
| `pointfreeco/swift-custom-dump` | `from: "1.3.2"` | Test targets |
| `pointfreeco/swift-snapshot-testing` | `from: "1.17.0"` | Test targets |
| `pointfreeco/xctest-dynamic-overlay` | `from: "1.2.2"` | Helpers, Auth, Realtime, Supabase (+ tests) |
| `WeTransfer/Mocker` | `from: "3.0.0"` | TestHelpers, FunctionsTests, PostgRESTTests, StorageTests |

**Note**: `xctest-dynamic-overlay` (via `IssueReporting`) is a production dependency — not just for tests.

## Architecture Notes

### Client Initialization

```swift
let supabase = SupabaseClient(
  supabaseURL: URL(string: "https://xyz.supabase.co")!,
  supabaseKey: "your-anon-key",
  options: SupabaseClientOptions(
    auth: .init(storage: MyCustomStorage()),
    db: .init(encoder: myEncoder, decoder: myDecoder),
    global: .init(headers: ["X-Custom": "header"])
  )
)

// Access sub-clients
supabase.auth          // AuthClient (actor)
supabase.database      // PostgrestClient
supabase.storage       // SupabaseStorageClient
supabase.realtimeV2    // RealtimeClientV2
supabase.functions     // FunctionsClient (actor)
```

### HTTP Layer

- `Helpers/HTTP/` contains the core `HTTPClient` protocol and implementations
- `LoggerInterceptor` logs requests/responses
- `RetryRequestInterceptor` retries on 503, 520, and network errors
- `StorageHTTPClient` abstraction in Storage allows custom HTTP implementations

### AnyJSON

`Sources/Helpers/AnyJSON/` provides `AnyJSON` for representing dynamic/untyped JSON values. Used throughout the SDK when JSON structure is not known at compile time.

### Version Tracking

`Sources/Helpers/Version.swift` tracks the current version (`2.48.0`). It is updated automatically by `release-please` via the `{x-release-please-version}` marker. The file also contains compile-time platform detection for user-agent strings.

## Commit Conventions

This project uses [Conventional Commits](https://www.conventionalcommits.org/) enforced by CI:

| Prefix | Effect |
|--------|--------|
| `feat:` | New feature → minor version bump |
| `fix:` | Bug fix → patch version bump |
| `docs:` | Documentation only |
| `test:` | Tests only |
| `refactor:` | Code restructuring |
| `perf:` | Performance improvement |
| `chore:` | Build/tooling changes |
| `feat!:` or `BREAKING CHANGE:` footer | Breaking change → major version bump |

Example: `feat(auth): add passkey authentication support`

## CI/CD

### GitHub Actions Workflows (8 files)

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | push/PR to main | Primary CI (see jobs below) |
| `release.yml` | CI success on main | Automated release via release-please |
| `api-stability.yml` | PR | Detects breaking API changes; requires `!` in title for breaking PRs |
| `conventional-commits.yml` | PR | Validates commit message format |
| `label-issues.yml` | Issues | Automatic labeling |
| `block-merge.yml` | PR | Blocks merge on specific labels |
| `stale.yml` | Schedule | Marks stale issues/PRs |
| `validate-capabilities.yml` | PR | Validates capability declarations |

### CI Jobs (ci.yml)

| Job | Runner | Xcode | Platforms tested |
|-----|--------|-------|-----------------|
| `macos` | macos-26 | 26.4 | IOS, MACOS (Debug test + Release build) |
| `macos-legacy` | macos-14 | 15.4 | IOS, MACOS, MAC_CATALYST (Debug test + Release build) |
| `spm` | macos-26 | — | SPM build (debug + release) |
| `linux` | ubuntu-latest | — | Build + unit tests (skips IntegrationTests) |
| `integration-tests` | ubuntu-latest | — | Full integration tests with live Supabase |
| `library-evolution` | macos-26 | 26.4 | ABI stability check |
| `examples` | macos-26 | 26.4 | Builds Examples, SlackClone, UserManagement schemes |
| `docs` | macos-26 | 26.4 | DocC documentation build validation |
| `format-check` | ubuntu-latest | — | **PR only** — format lint on changed files |
| `ci-success` | — | — | Aggregates all job statuses |

Coverage is generated for the `IOS` + `test` matrix entry and uploaded to Coveralls.

## Support Policy

- **Xcode**: Only versions eligible for App Store submission; dropping old versions is NOT a breaking change
- **Swift**: Minimum from oldest-supported Xcode (currently 5.10)
- **Platforms**: Four latest major versions (current + 3 previous)

## Common Tasks

### Adding a New Feature

1. Create feature branch from `main`
2. Implement with tests (use snapshot testing for complex structures)
3. Run `make format`
4. Run `swift test` to verify all tests pass
5. Add DocC documentation comments to new public APIs
6. Create PR with conventional commit title (e.g., `feat(storage): add resumable uploads`)
7. Ensure CI passes, including `format-check`

### Fixing a Bug

1. Add a failing test that reproduces the bug
2. Fix the bug
3. Run `make format` and `swift test`
4. Create PR with `fix:` prefix

### Adding Experimental APIs

Gate new experimental APIs with `@_spi(Experimental)`. See `Sources/Supabase/Exports.swift` and `Sources/Auth/WebAuthn/` for examples.

### Updating Dependencies

Edit version ranges in `Package.swift`. Prefer version ranges (`from:`) over exact versions for flexibility. Regenerate `Package.resolved` by building.

### Working with Integration Tests

```bash
# Requires Supabase CLI installed
cd Tests/IntegrationTests
supabase start
supabase db reset
cd ../..
INTEGRATION_TESTS=1 swift test --filter IntegrationTests
cd Tests/IntegrationTests
supabase stop
```

The `make test-integration` target handles this sequence automatically.

### Checking for Breaking API Changes

```bash
./scripts/check-for-breaking-api-changes.sh
```

This is also run automatically by the `api-stability.yml` workflow on PRs.

## Important Notes for AI Coding Agents

- **Always run `make format` before committing** — the `format-check` CI job will fail otherwise
- Ensure new public APIs have DocC documentation comments (`///`)
- Add tests for all new functionality; use snapshot testing for complex request/response structures
- Keep changes minimal and focused; don't introduce abstractions beyond the task
- `StrictConcurrency` and `ExistentialAny` are enabled — write Swift 6-compatible code
- Maintain `Sendable` conformance for all public types
- Use `RealtimeClientV2`/`RealtimeChannelV2` — not the deprecated classes in `Realtime/Deprecated/`
- `TestHelpers` is a production-compiled target (not a test target) — import it in test targets, not in production modules
- When adding async code, handle task cancellation properly
- The `xctest-dynamic-overlay` package (`IssueReporting`) is used in production code for soft assertions — this is intentional
- Check `sdk-compliance.yaml` when making API changes that might affect SDK compliance requirements
- Review the CI workflow jobs before pushing to understand what checks will run
- Snapshot reference files in `__Snapshots__/` directories must be committed with code changes
