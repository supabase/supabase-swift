---
name: swift-testing
description: >
  Use when writing or migrating tests in supabase-swift. Covers Swift Testing conventions
  (@Suite, @Test, #expect), HTTP mocking strategy (Replay vs Mocker), and the XCTest
  migration rules.
---

# Testing in supabase-swift

## Framework

New tests use Swift Testing, not XCTest. Both coexist in the same target during migration.

```swift
import Testing
@testable import ModuleName

@Suite
struct FeatureTests {
  @Test
  func featureBehavior() {
    #expect(result == expected)
  }
}
```

Rules:
- Always include `@Suite` (even with no custom name/tags)
- Drop the `test` prefix — `testFooBehavior` becomes `fooBehavior`
- Use `#expect` / `#require` instead of `XCTAssert*`
- `expectNoDifference`, `withExpectedIssue`, `assertSnapshot` work unchanged under both frameworks

## HTTP Mocking

| Module state | Mocking library |
|---|---|
| Migrated to Swift Testing | Replay — `@Test(.replay(...))`, HAR fixtures or inline `.replay(stubs:)` |
| Not yet migrated | Mocker — `URLSession` mock via `Mocker` |

## Running Tests

```bash
PLATFORM=IOS XCODEBUILD_ARGUMENT=test ./scripts/xcodebuild.sh
```

Never use `swift test` — use xcodebuild.

## Snapshot Testing

`assertSnapshot` / `assertInlineSnapshot` work inside `@Test` functions the same as `XCTestCase`. Use for complex response structures.

## Integration Tests

```bash
cd Tests/IntegrationTests && supabase start && supabase db reset && cd ../..
swift test --filter IntegrationTests
cd Tests/IntegrationTests && supabase stop
```
