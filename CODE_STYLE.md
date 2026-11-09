# Code Style and Conventions

## Swift Style

- Use 2 spaces for indentation (configured in `.editorconfig`)
- Enable strict concurrency checking (`StrictConcurrency` feature)
- Use `ExistentialAny` feature for explicit existential types
- Follow Swift API Design Guidelines
- Prefer `async/await` over completion handlers
- Mark types as `Sendable` where appropriate for concurrency safety

## Enum-like Values

- Use a Swift `enum` only when the value is genuinely closed: the cases carry associated values (`SignUpResult`, `SignedURLResult`, `RealtimeClientStatus`, `AuthStatus`), every case is fixed by the language or protocol itself (HTTP methods, a `CodingKeys` set), or the SDK has to implement each case so a value it has no code for is meaningless (`RealtimePostgresIsValue`). Adding a case to one of these is a major bump. Every public value enum is `Hashable` unless a payload cannot be.
- A status or event type the SDK produces follows one test: does any case carry a payload? If yes, it is an `enum`, and its doc comment says that new cases arrive only in a major release (`AuthStatus`, `RealtimeClientStatus`, `RealtimeChannelEvent`, `HeartbeatEvent`). If no, it is an open struct (`AuthEvent`).
- Any enum-like value sent to or received from the backend, and any payload-free status or event name a consumer will `switch` over (`AuthEvent`, `Provider`), must be a `RawRepresentable` struct instead, so a value the backend adds later (or that this SDK just doesn't have a case for yet) round-trips through `.rawValue` instead of failing to decode or blocking construction until an SDK upgrade. The consumer-facing policy lives in `Sources/Supabase/Supabase.docc/EnumsAndOpenSets.md`; keep it in sync when a type changes shape:

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
- Every open set has the same shape: `public let rawValue`, `init(rawValue:)`, `init(stringLiteral:)` (or `init(integerLiteral:)` for an `Int` set), and `Hashable & Sendable`, plus only the conformances its usage needs (see "Conform to exactly what the value's actual usage needs" above). It has no other initializers. Update `EnumsAndOpenSets.md` in the same commit when you add, remove, or change an enum or an open set.

## Naming

These rules add to the Swift API Design Guidelines. They make the same idea read the same way in every module.

- **Acronyms.** Write acronyms in uniform case in every public name: `ID`, `URL`, `URI`, `JWT`, `OTP` (`userID`, `redirectURL`, `jwksURI`; `id` and `url` when they start a name). Never write `Id`, `Url`, or `Uri`. When the wire key differs, map it in `CodingKeys` (see "Codable Conformance").
- **One concept, one type, one name.** A concept has one Swift type and one name, in requests and in responses. Links and endpoints are `URL`. An ID is `UUID` when the wire format guarantees a UUID. An opaque ID, such as the OAuth authorization ID, is `String`. Spans are `Duration`, and points in time are `Date`; never `TimeInterval`. A typed wrapper the SDK accepts (`CacheControl`, `WebSocketCloseCode`) is also the type it returns. Metadata is `JSONObject`, not a spelled-out `[String: JSONValue]`.
- **Same setting, same name.** A setting that means the same thing in two modules has the same name and type (`redirectTo`, `observesAppLifecycle`, `retryEnabled`, `clock`). A facade option has the same name as the module field it forwards to.
- **Booleans.** Boolean properties and settings read as assertions: `isEnabled`, `isPrivate`, `observesAppLifecycle`.
- **Type suffixes.** `<Action>Options` is a struct of optional request settings (see "Method Parameters"). `<Noun>Result` is a closed enum of outcomes. `<Noun>Page` is one page of a paged list. `<Owner>Status` is a state value. A request payload is named for its action (`CreateOAuthClient`), not `*Params` or `*Attributes`, and is passed without a label. A plain value gets a plain noun.
- **Verbs.** Resource methods on a client use `list<Noun>s`, `<noun>(id:)`, `create<Noun>(_:)`, `update<Noun>(id:_:)`, and `delete<Noun>(id:)`. A namespaced sub-client (`admin.customProviders`) uses the bare verbs: `list`, `create`, `update`, `delete`.
- **Labels.** A label names the entity it identifies: `revokeGrant(clientID:)`, not `revokeGrant(id:)`, when the argument is a client's ID. One argument has one label across overloads and modules.

## Models

- A public response or model struct has `public var` stored properties and a public memberwise init, so apps can build fixtures and previews. Do not mix `let` and `var` in one type.
- A response wrapper uses `status: HTTPResponse.Status`, `headers: HTTPFields`, `body` (`Data` or `HTTPBody`), and `requestID: String?`.
- A per-call `encoder:` or `decoder:` parameter is `JSONEncoder?` or `JSONDecoder?` with a default of `nil`. `nil` means the client's configured coder. Do not expose shared static coder instances.

## Client Configuration

- Client setup types end in `Configuration`. Per-call settings end in `Options` (see "Method Parameters"). Never use one suffix for the other, and never use `Config`.
- Each module client has `init(configuration: <Module>Client.Configuration)`. The configuration is a struct nested in the client, and it holds every setting, `url` included. Clients have no flat convenience inits.
- Each client exposes the value it was created with as `public let configuration`. Every configuration field is `public var`.
- Configuration init parameters come in this order: `url`, required module fields, `headers: HTTPFields = [:]`, optional module fields, `http: HTTPClientConfiguration`, `logger: Logger` (never optional; defaults to `supabaseDefaultLogger(label: "io.supabase.<module>")`), `encoder`/`decoder`, `retryEnabled`, `clock`.
- An HTTP module has no `accessToken` setting. The caller adds `AccessTokenMiddleware` to `http.middlewares`; that is the one way to put a token on a request (see ARCHITECTURE.md "HTTP Layer"). Realtime is the one exception: its socket needs the token outside any HTTP request, so `RealtimeClient.Configuration.accessToken` is its only token source, and it also covers `httpSend`.
- Every module that retries takes `retryEnabled:`. Every module that waits or retries takes `clock:`.
- The facade follows the same naming: `SupabaseClient(supabaseURL:supabaseKey:configuration:)` takes a `SupabaseClient.Configuration`, with one nested type per sub-client (`SupabaseClient.Configuration.Auth`, `.Database`, `.Storage`, `.Functions`, `.Realtime`) and `.Global` for shared settings. A facade type never reuses a module configuration type, because the facade derives `url` and the key itself.
- Public header APIs use `HTTPFields` and `HTTPField.Name`, never `[String: String]`.

## Streams and Events

- Every observable source is a method that returns a stream, never a callback or a token. A snapshot property may sit beside it, but the stream itself is never a property. Name it `statusChanges()` for state, and `events()` or `<noun>s()` for discrete events. A `status` snapshot property sits next to `statusChanges()`.
- A state stream emits the current value first, then every change. An event stream never replays.
- Status and event streams are `AsyncStream` and never throw; a failure shows up in the status. Data streams and paged sequences can throw.
- Each call returns a new stream for one consumer. The stream ends when the consuming task is cancelled or when the owner is released.
- A one-shot call takes a `progress:` closure. A long-lived handle exposes progress as a stream.
- A paged endpoint returns an `AsyncSequence` of elements that also offers `.pages`. The page-size parameter is `pageSize`.

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
   `listUsers(page:pageSize:)`, `info(path:versionId:)`, `disconnect(code:reason:)`.
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
- SDK models map wire keys with explicit `CodingKeys` that spell the literal wire key
  (`case userID = "user_id"`). Do not set `keyDecodingStrategy` or `keyEncodingStrategy` on SDK
  coders: a key strategy fights acronym names and silently drops fields that have their own
  `CodingKeys`.

## Error Handling

- Report issues using `IssueReporting` (from swift-issue-reporting on Swift 6.4+, from
  xctest-dynamic-overlay on earlier toolchains — see the comment atop `Package@swift-6.2.swift`)

### The error model

- **One error per module.** Each module has one public error struct, `<Module>Error`. It conforms
  to `SupabaseError` and lives in its own module, never in Helpers. Its fields are `kind`,
  `message`, `code`, `response`, and `underlyingError`. Errors are not `Equatable`. Public API uses
  untyped `throws`.
- **Kinds.** `Kind` is a nested open-set struct. Every module defines `server`, `transport`,
  `decoding`, and `invalidRequest`. Every module that can send an access token also defines
  `accessToken`. A module adds its own kinds only for failures these cannot describe
  (`sessionMissing`, …). Every kind a module throws is public.
- **Server codes.** A machine-readable code from the server is `public var code: <Module>Error.Code?`.
  `Code` is a nested open set (see "Enum-like Values"). It is `nil` when the server sent no code;
  never use a placeholder such as `.unknown`. Store the code once.
- **Retry classification.** `isRetryable` is a computed requirement of `SupabaseError`. One shared table
  derives it from `kind` and `response?.statusCode`. It is never stored and never an init
  parameter.
- **Wrapping.** A client-side refusal (a value that cannot be encoded, a URL that cannot be built)
  is `.invalidRequest`, with the cause in `underlyingError`. A `DecodingError` from a 2xx body is
  `.decoding`. A `URLError` is `.transport`; an HTTP timeout is `.transport` with
  `URLError(.timedOut)`. An HTTP rejection is `.server`, or a module kind chosen from the status,
  with `response` set. A failure in an access-token provider (`AccessTokenMiddleware`, the facade's
  Auth middleware, or Realtime's `accessToken`) is `.accessToken`. Raw Foundation or
  Helpers errors do not escape. If one must, the method's `- Throws:` names it.
- **Cancellation.** A cancelled task always surfaces as `CancellationError`, never wrapped. So does
  a cancellation the SDK causes for the caller: `disconnect()`, sign-out, `cancel()`, or a sheet the
  user dismisses. `HTTPClient` maps `URLError(.cancelled)` once, for the response head and the
  body. Modules do not repeat that mapping.
- **Error bodies.** `HTTPErrorResponse.body` keeps at most the first 1 MiB. Helpers applies the cap
  in one place.
- **Description.** `description` and `errorDescription` come from the shared `SupabaseError`
  implementation. Modules do not override them.
- **Pattern matching.** Every `Kind` and `Code` has a `~=` against `any Error`, so
  `catch StorageError.Kind.server` works in every module, as it does in Auth today.

### When trapping is allowed

The dividing line is *who can reach the value*, not who supplied it.

- **Public initializers throw on a bad configuration.** A server builds clients at runtime from
  configuration that varies per tenant, so a bad URL there is dynamic input, not a programmer
  error. Every client initializer (`SupabaseClient`, `AuthClient`, `PostgrestClient`,
  `StorageClient`, `FunctionsClient`, `RealtimeClient`) throws its module error with kind
  `invalidConfiguration` when the URL has no scheme or no host.
- **Internal invariants trap.** When the SDK has already checked a value, or builds it itself,
  `precondition`/`preconditionFailure` (or `try!` on a call that cannot fail for that value) is
  the right tool: a failure is an SDK bug. `SupabaseClient` checks `supabaseURL` once, so the
  getters that build its sub-clients use `try!`. A `package` tuning constant
  traps too.
- **Varies at runtime, or comes from the server** — a per-call parameter, a response header, a
  decoded payload, a WebSocket close code. Never trap. Throw if the context already throws;
  otherwise `reportIssue` and fall back.

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
- Stub HTTP at the `ClientTransport` seam with `ClosureTransport` or `RecordingTransport` from
  TestHelpers, passed as `http: HTTPClientConfiguration(transport:)`. Facade tests pass it through
  `global.http`. Use `URLProtocol` only in `URLSessionTransportTests`. Do not copy these stubs into
  a test target. Some older tests still use Mocker; do not add new ones (SDK-2883).
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

## Documentation

- Every public symbol has a `///` summary, including the static members of open sets and the
  properties of error structs.
- Every public `throws` function has a `- Throws:` line that names the module error and the
  conditions.
- Every library product has a `Sources/<Module>/<Module>.docc` catalog. Its landing page follows one
  template: a one-line summary, `## Overview`, then `## Topics` with `### Essentials` (the
  articles), the type groups, and `### Errors` last. Each catalog has a `HandlingErrors` article
  that lists every error that can escape unwrapped. A module that can run without
  `SupabaseClient` also has a `Standalone` article. Article titles use Title Case.
- Every type a doc names must exist. A public-API doc (a DocC article, `EnumsAndOpenSets.md`) names
  only public types. Contributor docs (this file, ARCHITECTURE.md) may also name `package` types.

