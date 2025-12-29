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

- Xcode 16.3+ (supports versions eligible for App Store submission)
- Swift 6.1+
- Supported platforms: iOS 13.0+, macOS 10.15+, tvOS 13+, watchOS 6+, visionOS 1+
- Linux is supported for building but not officially supported for production use

### Build Commands

```bash
# Build the package
swift build

# Build for specific configuration
swift build -c debug
swift build -c release

# Build with library evolution
make build-for-library-evolution

# Build using Xcode
make PLATFORM=IOS xcodebuild
make PLATFORM=MACOS xcodebuild
```

### Testing Commands

```bash
# Run all tests via Swift Package Manager
swift test

# Run tests for a specific module
swift test --filter AuthTests
swift test --filter StorageTests

# Run tests via Xcode
make PLATFORM=IOS XCODEBUILD_ARGUMENT=test xcodebuild

# Run integration tests (requires Supabase instance)
make test-integration

# Generate code coverage
make coverage
```

### Code Formatting

```bash
# Format all Swift files
make format
```

This uses `swift-format` to automatically format code. All code should be formatted before committing.

### Documentation

```bash
# Test documentation build
make test-docs
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

- Use XCTest framework
- Test files should mirror source file structure (`Foo.swift` → `FooTests.swift`)
- Use `@testable import` for internal access
- Use snapshot testing for complex data structures (via swift-snapshot-testing)
- Use Mocker for URLSession mocking in unit tests
- Use CustomDump for test assertions with better output
- Keep integration tests separate in `IntegrationTests` directory

Example test structure:

```swift
import XCTest
@testable import ModuleName

final class FeatureTests: XCTestCase {
  func testFeatureBehavior() {
    // Arrange
    let input = "test"
    
    // Act
    let result = feature(input)
    
    // Assert
    XCTAssertEqual(result, expected)
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
3. Run `make format` to format code
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

- Always run `make format` before committing Swift code
- Ensure new public APIs have DocC documentation comments
- Add tests for all new functionality
- Keep changes minimal and focused
- Respect the existing architecture and patterns
- Check that changes work on all supported platforms when possible
- Use snapshot testing for complex response structures
- Maintain Sendable conformance for Swift 6 compatibility
- When adding async code, ensure proper task cancellation handling
- Review the CI workflow to understand what checks will run
