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

### Linting

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

### Error Handling

- Use strongly-typed errors conforming to `Error` protocol
- Provide `LocalizedError` conformance where appropriate
- Use `async throws` for async error handling
- Report issues using `IssueReporting` from xctest-dynamic-overlay

### Testing Conventions

The test suite is migrating from XCTest to the [Swift Testing](https://developer.apple.com/documentation/testing) framework, module by module (tracked in [SDK-435](https://linear.app/supabase/issue/SDK-435)). New test files use Swift Testing; existing files keep working under XCTest until their module's migration phase lands — both coexist fine in the same target.

- Test files should mirror source file structure (`Foo.swift` → `FooTests.swift`)
- Suite naming: the type name matches the file name (`FooTests.swift` → `struct FooTests`), with an explicit `@Suite` attribute even when no custom name/tags are needed
- Test function names drop the `test` prefix (the `@Test` attribute already conveys that) — `testFooBehavior()` becomes `fooBehavior()`
- Use `@testable import` for internal access
- Prefer `#expect`/`#require` over `XCTAssert*` family; `#expect(x != nil, "message")` reads the same as the old `XCTAssertNotNil(x, "message")`
- `expectNoDifference` (CustomDump) and `withExpectedIssue`/`reportIssue` (IssueReporting) work under both frameworks unchanged — no conversion needed at call sites
- Use snapshot testing for complex data structures (via swift-snapshot-testing); `assertSnapshot`/`assertInlineSnapshot` work inside `@Test` functions the same as `XCTestCase`
- For HTTP mocking: modules already migrated to Swift Testing use [Replay](https://github.com/mattt/Replay) (`@Test(.replay(...))`, HAR fixtures or inline `.replay(stubs:)`) instead of Mocker — see SDK-435 phase issues for the migration order. Un-migrated modules keep using Mocker for URLSession mocking until their phase lands
- Use CustomDump for test assertions with better output
- Keep integration tests separate in `IntegrationTests` directory
- Test targets get full Swift 6 language mode checking (matching production targets) once migrated — see the `swift6TestTargets` set in `Package.swift`

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
swift test --filter IntegrationTests
cd Tests/IntegrationTests
supabase stop
```

## Important Notes for AI Coding Agents

- Always run `./scripts/format.sh` before committing Swift code
- Run `swiftlint lint --strict` before committing; it must not report new violations
- Ensure new public APIs have DocC documentation comments
- Add tests for all new functionality
- Keep changes minimal and focused
- Respect the existing architecture and patterns
- Check that changes work on all supported platforms when possible
- Use snapshot testing for complex response structures
- Maintain Sendable conformance for Swift 6 compatibility
- When adding async code, ensure proper task cancellation handling
- Review the CI workflow to understand what checks will run
