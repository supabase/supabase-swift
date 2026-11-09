# Code Style and Conventions

## Swift Style

- Use 2 spaces for indentation (configured in `.editorconfig`)
- Enable strict concurrency checking (`StrictConcurrency` feature)
- Use `ExistentialAny` feature for explicit existential types
- Follow Swift API Design Guidelines
- Prefer `async/await` over completion handlers
- Mark types as `Sendable` where appropriate for concurrency safety

## Enum-like Values

- Use a Swift `enum` only when the value is genuinely closed: the cases carry associated values (`AuthResponse`, `SignedURLResult`, `RealtimeClientStatus`), the SDK alone produces the value and it never crosses the wire (`RealtimeChannelEvent`, `HeartbeatEvent`), every case is fixed by the language or protocol itself (HTTP methods, a `CodingKeys` set), or the SDK has to implement each case so a value it has no code for is meaningless (`AuthFlowType`, `RealtimePostgresIsValue`). Adding a case to one of these is a major bump.
- Any enum-like value sent to or received from the backend, and any status or event value a consumer will `switch` over (`AuthChangeEvent`, `PushStatus`), must be a `RawRepresentable` struct instead, so a value the backend adds later (or that this SDK just doesn't have a case for yet) round-trips through `.rawValue` instead of failing to decode or blocking construction until an SDK upgrade. The consumer-facing policy lives in `Sources/Supabase/Supabase.docc/EnumsAndOpenSets.md`; keep it in sync when a type changes shape:

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

## Method Parameters: Inline or Options

Use these rules for every public method. Apply them in order.

1. Inline the values that identify the target or the action: the required inputs (`path`,
   `provider`, `email`, `token`, `type`) and the source and destination of a move or copy
   (`toBucket`, `sourceVersionId`). These are always inline, even when they are optional. An
   optional value that only selects a variant of the result, such as `versionId` or `transform`
   on a URL, is a setting, not an identifier.
2. Put optional request settings in an `<Action>Options` struct when one of these is true:
   - The method has three or more optional settings.
   - The method shares a group of two or more settings with another method. A single shared
     setting is not a group. For example, `redirectTo` and `captchaToken` together appear in
     `signInWithSSO`, `resend`, and `resetPassword`. `download` and `cacheNonce` together appear
     in `createSignedURL`, `createSignedURLs`, and `publicURL`.
   - The method already takes an options struct. Then all of its optional settings go in that
     struct, as `transform` does in `DownloadOptions`.
3. Overloads of one method use the same shape. `resend(phone:type:options:)` takes options
   because `resend(email:type:options:)` does, even though it has only one setting. This rule
   wins over rule 4.
4. Otherwise, one or two optional settings stay inline when the matching supabase-js method has
   no more optional settings than these. A lone `captchaToken` or `redirectTo` is fine:
   `signIn(email:password:captchaToken:)`, `signInAnonymously(userMetadata:captchaToken:)`,
   `updateUser(_:redirectTo:)`, `createSignedUploadURL(path:upsert:)`,
   `listUsers(page:perPage:)`, `info(path:versionId:)`, `disconnect(code:reason:)`.
5. The options parameter is named `options` and has a default of an empty value (`.init()` or
   `XOptions()`). It comes after the required inputs. It comes before the parameters that are not
   request settings, which always stay inline: `presenter`, `progress`, `as:`, `decoder`,
   `encoder`, and the payload (`body`, `values`).

Rule 2 decides whether settings go in a struct. It does not mean that methods share one struct.
Give each method (or each overload family) its own options type, even when two types have the
same fields today, as `SSOOptions` and `ResetPasswordOptions` do. The server can add a field to
one action and not the other. Methods that send the same request share a type, as `upload`,
`update`, and `uploadToSignedURL` share `UploadOptions`. Mirror the field names of supabase-js
where they exist, and follow the Swift API Design Guidelines for the type and parameter names.

These are deliberate exceptions. They keep their inline parameters:

- PostgREST builder modifiers: `select`, `insert`, `upsert`, `update`, `delete`, `order`,
  `explain`, `textSearch`, and `rpc`. Each call is one step in a chain, and its labels read like
  the SQL clause they make.
- Realtime `postgresChanges(...)`. Its parameters describe the subscription, so rule 1 applies.
- Initializers of configuration, model, error, and options types.

## File Headers

Use standard file headers with copyright:

```swift
//
//  FileName.swift
//  ModuleName
//
//  Created by Author Name on DD/MM/YY.
//
```

## Module Organization

- Each module is independent and can be used standalone
- Use `@_exported import` in main Supabase module to re-export all sub-modules
- Keep module dependencies minimal
- Prefer protocol-oriented design

## Codable Conformance

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
  is actually used. See `docs/migrations/v3/` for prior cleanup along these
  lines (the SDK-1473 pass).

## Error Handling

- Use strongly-typed errors conforming to `Error` protocol
- Provide `LocalizedError` conformance where appropriate
- Use `async throws` for async error handling
- Report issues using `IssueReporting` (from swift-issue-reporting on Swift 6.4+, from
  xctest-dynamic-overlay on earlier toolchains — see the comment atop `Package@swift-6.2.swift`)

### When trapping is allowed

The dividing line is *who can reach the value*, not who supplied it.

- **Public initializers throw on a bad configuration.** A server builds clients at runtime from
  configuration that varies per tenant, so a bad URL there is dynamic input, not a programmer
  error. `SupabaseClient.init`, `StorageClient.init(configuration:)` and
  `FunctionsClient.init(configuration:)` throw their module error with kind
  `invalidConfiguration`.
- **Internal invariants trap.** When the SDK has already checked a value, or builds it itself,
  `precondition`/`preconditionFailure` (or `try!` on a call that cannot fail for that value) is
  the right tool: a failure is an SDK bug. `SupabaseClient` checks `supabaseURL` once, so its
  `storage` and `functions` getters build their clients with `try!`. A `package` tuning constant
  traps too.
- **Varies at runtime, or comes from the server** — a per-call parameter, a response header, a
  decoded payload, a WebSocket close code. Never trap. Throw if the context already throws;
  otherwise `reportIssue` and fall back. `HTTPFields.init(_:)` drops invalid field names rather
  than trapping precisely because `HTTPResponse.init` builds it from `response.allHeaderFields`,
  which a proxy or a hostile server controls.

Degrading instead of throwing would bury the mistake behind an unrelated failure much later. See
SDK-1793.

## Testing Conventions

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

