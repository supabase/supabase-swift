# Instructions for supabase-swift

## Repository Overview

This is the official Supabase SDK for Swift, mirroring the design of supabase-js. It provides a Swift client for interacting with Supabase services including Auth, Database (PostgREST), Realtime, Storage, and Functions.

## Project Structure

- `Sources/`: Source code organized by module
  - `Auth/`: Authentication module
  - `Functions/`: Edge Functions client
  - `PostgREST/`: Database client
  - `Realtime/`: Realtime subscriptions
  - `Storage/`: File storage client
  - `Supabase/`: Main client that integrates all modules
  - `Helpers/`: Shared utilities
  - `TestHelpers/`: Test utilities
- `Tests/`: Unit and integration tests organized by module
- `Examples/`: Example applications demonstrating SDK usage
- `docs/`: Documentation files

## Development Environment

### Requirements

- Xcode 16.4+ (supports versions eligible for App Store submission)
- Swift 6.1+
- Supported platforms: iOS 16.0+, macOS 13.0+, tvOS 16+, watchOS 9+, visionOS 1+
- Linux is supported for building but not officially supported for production use

### Build Commands

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

### Testing Commands

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

# Generate code coverage
DERIVED_DATA_PATH=~/.derivedData/Debug ./scripts/generate-coverage.sh
```

### Code Formatting

```bash
# Format all Swift files
./scripts/format.sh
```

This uses `swift-format` to automatically format code. All code should be formatted before committing.

### Spell Checking

Spell-checking uses [cSpell](https://cspell.org), via Node/npm:

```bash
npm ci --prefix tools/node   # one-time setup (re-run only when tools/node/package-lock.json changes)
./scripts/spell-check.sh     # cspell - Swift and Markdown sources
```

Legitimate technical terms and project-specific words go in `dictionary.txt` at the repository root.

### Documentation

```bash
# Test documentation build
./scripts/test-docs.sh
```

Ensures DocC documentation builds without warnings.

## Code Style and Conventions

### Swift Style

- Use 2 spaces for indentation (configured in `.editorconfig`)
- Enable strict concurrency checking (`StrictConcurrency` feature)
- Use `ExistentialAny` feature for explicit existential types
- Follow Swift API Design Guidelines
- Prefer `async/await` over completion handlers
- Mark types as `Sendable` where appropriate for concurrency safety

### Enum-like Values

- Use a Swift `enum` only when the value is genuinely closed: every case is fixed by the language or protocol itself (HTTP methods, a `CodingKeys` set) or the value is entirely client-side and never crosses the wire (e.g. `AuthChangeEvent`, `LogLevel`).
- Any enum-like value sent to or received from the backend must be a `RawRepresentable` struct instead, so a value the backend adds later (or that this SDK just doesn't have a case for yet) round-trips through `.rawValue` instead of failing to decode or blocking construction until an SDK upgrade:

  ```swift
  public struct Provider: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
      self.init(rawValue: value)
    }

    public static let apple: Provider = "apple"
    public static let github: Provider = "github"
  }
  ```

- Conform to exactly what the value's actual usage needs — `Codable` only if it's ever decoded, `Encodable`-only if it's write-only, no `Codable`/`Encodable` at all if it's read via `.rawValue` directly into a header or query string (never through `JSONEncoder`/`JSONDecoder`). Don't upgrade a type's conformance just because a sibling type in the same file has more.
- Don't add a `CaseIterable`/`Identifiable` replacement (a `knownCases` array, a custom `Identifiable`) to the SDK type unless something inside this package actually needs one — a consuming app can keep its own list of the values it cares about (see `Examples/Examples/Auth/KnownProviders.swift`).
- `init(rawValue:)` is intentionally non-failable — it always succeeds, which is what makes constructing/decoding an unrecognized value safe instead of an error. Any breaking-change migration note for a type like this must call out that `if let x = X(rawValue:)` goes from compiling to a compile error, and that interpolating the value directly (`"\(x)"`) silently stops printing the case name.

### File Headers

Use standard file headers with copyright:

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
- Use `@_exported import` in main Supabase module to re-export all sub-modules
- Keep module dependencies minimal
- Prefer protocol-oriented design

### Codable Conformance

- Only conform a type to the direction the SDK actually uses: a type the SDK
  only decodes from a server response gets `Decodable`, a type the SDK only
  encodes into a request body gets `Encodable`. Conform to full `Codable`
  only when the same type is genuinely used in both directions (e.g. a type
  the SDK both sends and receives over the wire, or persists to disk via
  `JSONEncoder`/`JSONDecoder`, like Auth's `Session`).
- Before narrowing a type from `Codable` to `Decodable`/`Encodable`, check
  whether any other type embeds it and relies on synthesized `Codable` — a
  container relying on synthesized conformance stops compiling the moment a
  field it holds drops the direction the container needs, so the container
  must narrow the same way (or gain its own hand-written coder). The same
  check applies in reverse when widening a type back toward `Codable`: every
  stored property must be at least as conformant as the type you're widening
  to.
- Don't hand-write `encode(to:)`/`init(from:)` for the unused direction "for
  symmetry" — dead coders accumulate and mislead readers about how the type
  is actually used. See `V3_MIGRATION.md` for prior cleanup along these
  lines (`VerifyOTPResponse`, and the broader SDK-1473 pass).

### Error Handling

- Use strongly-typed errors conforming to `Error` protocol
- Provide `LocalizedError` conformance where appropriate
- Use `async throws` for async error handling
- Report issues using `IssueReporting` from xctest-dynamic-overlay

### Testing Conventions

This project uses the [Swift Testing](https://developer.apple.com/documentation/testing) framework, and only Swift Testing — do not use XCTest or `XCTestCase`.

- Test files should mirror source file structure (`Foo.swift` → `FooTests.swift`)
- Suite naming: the type name matches the file name (`FooTests.swift` → `struct FooTests`), with an explicit `@Suite` attribute even when no custom name/tags are needed
- Test function names drop the `test` prefix (the `@Test` attribute already conveys that) — write `fooBehavior()`, not `testFooBehavior()`
- Use `@testable import` for internal access
- Prefer `#expect`/`#require` for assertions; `#expect(x != nil, "message")` reads the same as `XCTAssertNotNil(x, "message")` did
- `expectNoDifference` (CustomDump) and `withExpectedIssue`/`reportIssue` (IssueReporting) work unchanged at call sites
- Use snapshot testing for complex data structures (via swift-snapshot-testing); `assertSnapshot`/`assertInlineSnapshot` work inside `@Test` functions
- Use Mocker for URLSession mocking
- Use CustomDump for test assertions with better output
- Keep integration tests separate in `IntegrationTests` directory
- Test targets get full Swift 6 language mode checking, matching production targets

Example test structure (Swift Testing):

```swift
import Testing
@testable import ModuleName

@Suite
struct FeatureTests {
  @Test
  func featureBehavior() {
    // Arrange
    let input = "test"

    // Act
    let result = feature(input)

    // Assert
    #expect(result == expected)
  }
}
```

## Dependencies

### Core Dependencies

- `swift-crypto`: Cryptographic operations
- `swift-http-types`: Modern HTTP types
- `swift-clocks`: Time-based operations
- `swift-concurrency-extras`: Concurrency utilities

### Test Dependencies

- `swift-snapshot-testing`: Snapshot testing
- `swift-custom-dump`: Better test output
- `xctest-dynamic-overlay`: Test utilities and issue reporting
- `Mocker`: URL mocking

## Architecture Notes

### Client Initialization

The main `SupabaseClient` acts as a facade for all sub-clients (Auth, Database, Storage, Functions, Realtime). Each sub-client can also be used independently.

### Async/Await

The SDK is fully async/await based. Avoid using completion handlers in new code.

### Sendable Conformance

All public types should conform to `Sendable` where appropriate for Swift 6 compatibility.

### HTTP Layer

Uses modern `HTTPTypes` for request/response handling. Custom `StorageHTTPSession` abstraction allows for testing and custom implementations.

### Generated OpenAPI Clients

Some modules ship a low-level HTTP client generated from an OpenAPI spec, living under `Sources/<Module>/Generated/` (e.g. `Sources/Storage/Generated/`). These files are produced by `tools/openapi-codegen`, a standalone SwiftPM CLI tool in this repo (not published), from a spec in `openapi/<module>.json`.

To regenerate all clients:

```bash
./scripts/generate-openapi-clients.sh
```

This rebuilds `tools/openapi-codegen`, regenerates `Models.swift` and `Client.swift` for each module listed in the script's `MODULES` array, and runs `./scripts/format.sh` on the output. Never hand-edit files under a `Generated/` directory — edit the OpenAPI spec and regenerate instead.

Generated declarations are nested under a per-module namespace enum (e.g. `enum StorageBackendAPI { ... }`, with the client at `StorageBackendAPI.Client`) so schema-derived type names can never collide with hand-written public types in the same module, regardless of what the spec names things.

To wire up a new module: add `openapi/<module>.json`, add the module name to `MODULES` in `scripts/generate-openapi-clients.sh`, and run the script.

### Configuration

Uses option builder pattern for client configuration:

```swift
SupabaseClient(
  supabaseURL: url,
  supabaseKey: key,
  options: SupabaseClientOptions(
    auth: .init(...),
    db: .init(...),
    global: .init(...)
  )
)
```

## Commit Conventions

This project uses [Conventional Commits](https://www.conventionalcommits.org/) with release-please for automated versioning:

- `feat:` - New features (minor version bump)
- `fix:` - Bug fixes (patch version bump)
- `docs:` - Documentation changes
- `test:` - Test changes
- `refactor:` - Code refactoring
- `perf:` - Performance improvements
- `chore:` - Build/tooling changes
- `feat!:` or `BREAKING CHANGE:` - Breaking changes (major version bump)

Example: `feat(auth): add PKCE flow support`

The `!`/`BREAKING CHANGE:` marker is the same one release-please and the API stability check key
off to bump majors and flag reviewers. Every commit carrying it also requires an entry in the
root `V<N>_MIGRATION.md` — see the writing-migration-guides skill for the format.

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

## Common Tasks

### Adding a New Feature

1. Create feature branch from `main`
2. Implement feature with tests
3. Run `./scripts/format.sh` to format code
4. Run `swift test` to verify tests pass
5. Add documentation if needed
6. Create PR with conventional commit title
7. Ensure CI passes

### Fixing a Bug

1. Add a failing test that reproduces the bug
2. Fix the bug
3. Verify test now passes
4. Run full test suite
5. Create PR with `fix:` prefix

### Updating Dependencies

Dependencies are managed in `Package.swift`. Use version ranges when possible to allow flexibility.

### Working with Integration Tests

Integration tests require a local Supabase instance:

```bash
cd Tests/IntegrationTests
supabase start
supabase db reset
cd ../..
swift test --filter IntegrationTests --skip verifyOTPForSecureEmailChange
cd Tests/IntegrationTests
supabase stop
```

`verifyOTPForSecureEmailChange` needs `auth.email.enable_confirmations = true` to reach GoTrue's
secure-email-change "single confirmation" response, which every other integration test relies on
being `false` (so `signUp`/`signIn` resolve without confirming an email). It runs against a
second, minimal project instead of forking that setting for the whole suite:

```bash
cd Tests/IntegrationTests/supabase-secure-email-change
supabase start
cd ../../..
swift test --filter verifyOTPForSecureEmailChange
cd Tests/IntegrationTests/supabase-secure-email-change
supabase stop
```

## Important Notes for AI Coding Agents

- Always run `./scripts/format.sh` before committing Swift code
- Ensure new public APIs have DocC documentation comments
- Add tests for all new functionality
- Keep changes minimal and focused
- Respect the existing architecture and patterns
- Check that changes work on all supported platforms when possible
- Use snapshot testing for complex response structures
- Maintain Sendable conformance for Swift 6 compatibility
- When adding async code, ensure proper task cancellation handling
- Review the CI workflow to understand what checks will run
