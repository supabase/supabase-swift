# Design: supabase-swift as a server-side SDK

- **Status:** Draft
- **Date:** 2026-11-06
- **Author:** Guilherme Souza
- **Target:** v3 for the breaking-change audit (section 5). Later minor releases for the features.
- **Scope:** `Auth`, `PostgREST`, `Realtime`, `Storage`, `Functions`, `Supabase`, `Helpers`, CI, and docs

## 1. Summary

supabase-swift is built for apps on Apple platforms. It builds and passes unit tests on Linux,
but [DEVELOPMENT.md](../../../DEVELOPMENT.md) says Linux is "not officially supported for
production use."

This design makes the SDK a fully supported server-side SDK. Server code that uses Vapor,
Hummingbird, AWS Lambda, or plain SwiftNIO can then use it. The work fills specific gaps. It does
not rewrite the SDK. The public seams that a server needs (transport protocols, pluggable session
storage, local JWT verification) already exist.

### Release plan

- **v3 (in development, breaking changes allowed).** v3 ships only the breaking changes that server
  support needs. Section 5 audits the public API for them. The result: **no breaking change is
  strictly required.** v3 already removed the mobile-only shapes (see 5.1). v3 still takes one
  optional break: the client initializers throw instead of trapping (5.2, D1).
- **After v3 (additive minor releases).** All server features land in three phases (section 6):
  1. **Foundation.** NIO transports, request-scoped clients, a server preset, and official Linux
     support.
  2. **Server auth and operations.** A standalone JWT verifier, SSR cookie sessions, webhook
     signatures, service lifecycle, and tracing.
  3. **Ecosystem.** Vapor and Hummingbird integrations, a Lambda sample, and a spike on direct
     Postgres access.

## 2. Goals and non-goals

### Goals

- G1. Linux (glibc and the Static Linux SDK with musl) is a supported production platform. It has
  the same test coverage as macOS, integration tests included.
- G2. One process serves many users at the same time. Each request has a cheap, isolated client
  that uses that request's credentials. Clients share one connection pool.
- G3. A server never traps on bad runtime input, such as a tenant URL read from config.
- G4. No background work runs unless the caller asks for it. This covers auto refresh, lifecycle
  observers, and Realtime sockets.
- G5. The SDK fits the server-Swift ecosystem: SwiftNIO, AsyncHTTPClient, swift-log,
  swift-service-lifecycle, and swift-distributed-tracing.
- G6. A Swift backend can share a session with a supabase-js frontend through cookies.
- G7. Mobile users get no new dependencies and no behavior changes by default.

### Non-goals

- Writing Supabase Edge Functions in Swift. The Edge runtime is Deno.
- The Supabase Management API.
- Windows, Android, and WebAssembly. We can revisit them after Linux is solid.
- Replacing PostgREST as the main data path. Direct Postgres access is a spike only (section 4.13).

## 3. Current state

I checked these facts against the code on 2026-11-06.

| Area | Today | Where |
|---|---|---|
| Platforms | Apple platforms only in `platforms:`. Linux builds and runs unit tests in CI (`swift:6.2-noble`, `swift:6.3-noble`). | `Package.swift`, `.github/workflows/ci.yml` |
| Support policy | Linux "not officially supported for production use" | `DEVELOPMENT.md:10` |
| HTTP transport | Public `ClientTransport` protocol. The default and only implementation is `URLSessionTransport`. | `Sources/Helpers/HTTP/ClientTransport.swift:38`, `HTTPClientConfiguration.swift:72` |
| WebSocket transport | Public `WebSocketTransport` protocol. The only implementation is `URLSessionWebSocketTransport`. | `Sources/Realtime/Transport/` |
| Package traits | Already used for `OpenTelemetry` | `Package.swift:26` |
| Session storage | `AuthStorage` protocol, `KeychainStorage` (Apple only), `InMemoryAuthStorage` | `Sources/Auth/Storage/` |
| JWT verification | `AuthClient.claims(jwt:options:)` verifies locally through `JWKSCache`. **The cache belongs to one `AuthClient`.** | `Sources/Auth/AuthClient.swift:248`, `:1772` |
| Admin API | `AuthAdminClient` with MFA, OAuth, and custom providers | `Sources/Auth/AuthAdmin*.swift` |
| API keys | Knows the `sb_publishable_` and `sb_secret_` formats | `Sources/Helpers/APIKeyFormat.swift` |
| Third-party tokens | `SupabaseClientOptions.AuthOptions.accessToken` closure. When set, auto refresh is `.disabled` and no auth-event task runs. | `Sources/Supabase/Types.swift:105`, `SupabaseClient.swift:261` |
| Client construction | `SupabaseClient.init` builds an `AuthClient` eagerly. That creates a `JWKSCache`, loads the stored session, starts a lifecycle task, and starts a `Task { await autoRefresh.apply() }`. Realtime and Functions are lazy. PostgREST and Storage clients are built on each access. | `SupabaseClient.swift:214-269`, `AuthClient.swift:240-262` |
| Traps on input | `preconditionFailure` on a URL with no host (`SupabaseClient`), and on invalid URLs (`StorageAPI`, `StorageRequests`, `FunctionsClient`) | `SupabaseClient.swift:241`, `StorageAPI.swift:38,44`, `StorageRequests.swift:38,63`, `FunctionsClient.swift:129` |
| Storage streaming | Upload takes `HTTPBody` (an `AsyncSequence`) or a file URL. Download returns a streamed body. TUS resumable uploads exist. | `Sources/Storage/StorageBucket.swift`, `TusSession.swift` |
| Resumable registry | `ResumableStore` defaults to `.applicationSupportDirectory` | `Sources/Storage/ResumableStore.swift:65` |
| REST broadcast | `RealtimeChannel.httpSend` exists | `Sources/Realtime/RealtimeChannel+HTTPSend.swift` |
| Stream buffering | WebSocket events use `.unbounded` buffering. Some client-state streams use the default (also unbounded). | `URLSessionWebSocketTransport.swift:289`, `Realtime/Shell/ClientState.swift:108` |
| Logging and tracing | swift-log. OpenTelemetry behind a trait. `TraceContextMiddleware` on Auth requests. | `Package.swift`, `SupabaseClient.swift:259` |
| Apple-only code | Keychain, UIKit/AppKit lifecycle, `Network` path monitor, and `ASWebAuthenticationSession` are all behind `#if` | various |
| Cookies | No cookie support in Auth | — |

## 4. Design

### 4.1 Support tiers

| Tier | Platforms | Meaning |
|---|---|---|
| 1 | iOS, macOS, Linux (glibc, Ubuntu 22.04/24.04, Amazon Linux 2023) | Full unit and integration tests in CI. Bugs block releases. |
| 1 | Linux, Static Linux SDK (musl) | Build and unit tests in CI. Integration tests on glibc only. |
| 2 | tvOS, watchOS, visionOS, Mac Catalyst | Same as today |

Changes:

- Update `DEVELOPMENT.md`, the README "Supported platforms" section, and `RELEASE.md` if the
  release checklist names platforms.
- The minimum Swift version stays the same as on Apple platforms (6.2).

### 4.2 NIO transports

Add a new target, `SupabaseNIO`, behind a new package trait, `NIO`. The trait is off by default.
This follows the `OpenTelemetry` trait precedent and meets G7.

```swift
// Package.swift (sketch)
traits: [
  .trait(name: "OpenTelemetry"),
  .trait(name: "NIO"),
],
dependencies: [
  .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.24.0"),
  // WebSocket client: see open question Q2
],
targets: [
  .target(
    name: "SupabaseNIO",
    dependencies: [
      "Helpers", "Realtime",
      .product(name: "AsyncHTTPClient", package: "async-http-client",
               condition: .when(traits: ["NIO"])),
    ]
  ),
]
```

Types:

```swift
/// A ``ClientTransport`` built on AsyncHTTPClient.
public struct AsyncHTTPClientTransport: ClientTransport {
  public init(client: HTTPClient = .shared, configuration: Configuration = .init())
}

/// A ``WebSocketTransport`` built on SwiftNIO.
public struct NIOWebSocketTransport: WebSocketTransport {
  public init(eventLoopGroup: any EventLoopGroup = .singletonMultiThreadedEventLoopGroup)
}
```

Rules:

- The caller owns the `HTTPClient` lifecycle. The default is `HTTPClient.shared`, so most users
  never shut one down.
- Request and response bodies stream both ways. `HTTPBody` maps to AsyncHTTPClient request and
  response bodies with no full buffering.
- Task cancellation cancels the AsyncHTTPClient request.
- The per-request `timeout` from `HTTPClientConfiguration` maps to the AsyncHTTPClient deadline.
- The URLSession transports stay the default on every platform. The server preset (4.4) chooses
  the NIO transports.

Tests:

- Run the existing transport conformance tests against both transports.
- Add a Linux benchmark job: request throughput and p99 latency, `URLSessionTransport` against
  `AsyncHTTPClientTransport`.

### 4.3 Request-scoped clients

**Problem.** A server handles many users at the same time. Today a caller has two options. One is
to share a `SupabaseClient`, which holds one session and is wrong for many users. The other is to
build a new `SupabaseClient` per request. That builds an `AuthClient`, a fresh `JWKSCache`, and at
least one unstructured `Task` each time. A fresh JWKS cache also means a network fetch of the key
set on the first `claims(jwt:)` call of every request.

**Design.** Split `SupabaseClient` into a shared core and thin views.

```swift
// At boot. One per Supabase project.
let supabase = try SupabaseClient(
  supabaseURL: url,
  supabaseKey: publishableKey,
  options: .server()
)

// Per request.
let scoped = supabase.scoped(accessToken: bearerToken)
let todos: [Todo] = try await scoped.from("todos").select().execute().value
```

- `SupabaseClient.Core` (internal) holds the options, the HTTP configuration and transport, the
  `JWKSCache`, the logger, and the clock. Every scoped client shares one `Core`.
- `scoped(accessToken:)` returns a `SupabaseClient` with these properties:
  - Data requests (PostgREST, Storage, Functions) send the given token.
  - It does no eager work. It creates no `AuthClient`, starts no `Task`, and loads no session.
  - `auth` is not available. It reports an issue, as it does today with the `accessToken` option.
    Use `supabase.auth.claims(jwt:)` or `JWTVerifier` (4.6) instead.
  - `realtime` is lazy and belongs to the scoped client. Most request handlers never touch it.
- `scoped(accessToken:)` also takes an optional `Logger`, so log lines carry request metadata.

**Prerequisite refactor (internal).** `scoped(accessToken:)` builds its client through a new
internal path that skips `AuthClient`. The main `init` keeps building `_auth` eagerly, so mobile
behavior does not change. Move `JWKSCache` out of `AuthClient` into a type that `Core` can share.

**Target.** Creating a scoped client starts zero tasks and allocates no more than a few small
objects. A benchmark in CI guards this.

**Service role.** A client built with an `sb_secret_` key is already a service-role client. The
docs show the pattern: one service-role client for admin work, and scoped publishable clients for
user work.

### 4.4 Server preset

Add `SupabaseClientOptions.server(...)`:

| Option | Mobile default | `.server()` |
|---|---|---|
| `auth.autoRefresh` | `.automatic` | `.disabled` |
| `auth.observesAppLifecycle` | `true` | `false` |
| `auth.storage` | Keychain or in-memory | `InMemoryAuthStorage` |
| `global.http.transport` | `URLSessionTransport` | `AsyncHTTPClientTransport` when the `NIO` trait is on, otherwise `URLSessionTransport` |
| Realtime transport | `URLSessionWebSocketTransport` | `NIOWebSocketTransport` when the `NIO` trait is on |
| `storage.resumable` registry | Application Support | Off, or a directory the caller gives |

`.server()` takes overrides for each field. It adds no new behavior. It only picks values.

### 4.5 Throwing initialization

**Problem.** A server that reads tenant URLs from config at runtime crashes the whole process on
one bad value (see the traps in section 3). G3 forbids this.

[CODE_STYLE.md](../../../CODE_STYLE.md) ("When trapping is allowed", SDK-1793) allows the trap on
purpose. Its rule: a value fixed once, at construction, is a programmer error. A multi-tenant
server breaks that premise. It builds clients at runtime from dynamic config, and the same rule
says never to trap on a dynamic value.

**Decision (D1): option (a), in v3.** The options were:

- **(a) v3: the initializers throw.** Chosen.
- **(b) After v3: add `init(validating:) throws` next to the trapping initializers.** Rejected:
  two initializers forever.

**Design.**

- `SupabaseClient.init(supabaseURL:supabaseKey:options:)` and
  `init(supabaseURL:supabaseKey:)` throw a new `SupabaseClientError` with kind
  `.invalidConfiguration` when `supabaseURL` has no host. It follows the struct-with-`Kind`
  shape of the other module errors and conforms to `SupabaseError`.
- `StorageClient.init(configuration:)` throws `StorageError` with the new kind
  `.invalidConfiguration`.
- `FunctionsClient.init(configuration:)` throws `FunctionsError` with the new kind
  `.invalidConfiguration`.
- `supabase.storage` and `supabase.functions` do not throw. `SupabaseClient.init` checks the URL
  once, so the sub-client initializers cannot fail for the URLs derived from it.
- CODE_STYLE.md "When trapping is allowed" now says that public initializers throw on a bad
  configuration, and that only internal invariants trap.

Also:

- `StorageRequests` traps when it builds a URL for each request (`StorageRequests.swift:63`).
  The object key varies on each call, so CODE_STYLE.md already says it must throw. The method
  already throws, so this fix is not breaking. Ship it as a bug fix at any time.
- The `fatalError()` calls in `@available(*, unavailable)` stubs stay. No one can call them.

### 4.6 Request authentication

**Standalone verifier.** Add a type for middleware that needs only to verify tokens:

```swift
public struct JWTVerifier: Sendable {
  public init(supabaseURL: URL, http: HTTPClientConfiguration = .init())
  public func verify(_ token: String, options: ClaimsOptions = .init()) async throws -> VerifiedClaims
}
```

- It shares the JWKS cache logic with `AuthClient.claims(jwt:)`. One cache serves every request.
- It caches keys by `kid` and fetches the key set again on an unknown `kid`, with a rate limit, so a flood of bad
  tokens cannot cause a refetch storm.
- For legacy HS256 projects, the caller passes the JWT secret. `verify` then checks locally with no
  network call.
- It never calls `/user`. The docs explain when a server must still call `getUser` (to see a ban
  or a deleted user right away).

**Keys.** `APIKeyFormat` already knows `sb_secret_`. Add a debug-build runtime warning if a secret
key is used with a client that also uses a cookie session. That mix is a common mistake.

### 4.7 SSR cookie sessions

**Goal.** A Swift backend reads and writes the same session cookies as `@supabase/ssr`. A
Next.js or SvelteKit frontend and a Swift API then share one login.

**Design.** Add a framework-agnostic target, `SupabaseSSR`. It works on `HTTPTypes.HTTPFields`.
The `swift-http-types` package is already a dependency. Hummingbird 2 uses `HTTPTypes` directly,
and Vapor can bridge to it.

```swift
public struct CookieAuthStorage: AuthStorage {
  /// Reads the session from the request's `Cookie` header.
  public init(request: HTTPFields, options: CookieOptions = .init())
  /// The `Set-Cookie` fields to add to the response after the request.
  public func responseCookies() -> [HTTPField]
}
```

- Cookie names, chunking (`sb-<ref>-auth-token.0`, `.1`, ...), the `base64-` value prefix, and
  defaults (`Path=/`, `SameSite=Lax`, `HttpOnly` off so browser JS can read it, `Secure` in
  production) all match `@supabase/ssr`. Q4 tracks how we confirm the exact format.
- The PKCE code verifier is stored in a cookie too. A server-side `/auth/callback` can then call
  `exchangeCodeForSession` with no client state.
- Golden tests: fixtures with cookies that `@supabase/ssr` wrote, and the reverse direction.
- **PKCE interop.** v3 stores each pending flow under `<storageKey>-flow-<id>`, with an index at
  `<storageKey>-flows`. supabase-js stores one verifier at `<storageKey>-code-verifier`. In v3,
  `exchangeCodeForSession` throws when no Swift flow is stored. A Swift server that handles a
  callback for a flow that a JS frontend started then fails. Fix it additively: add an overload
  `exchangeCodeForSession(_:codeVerifier:)`, and have `CookieAuthStorage` read the JS verifier
  cookie.
- **Shared state.** `FlowIndexUpdateQueue` keeps a process-wide cache of queues by storage key
  (`FlowStore.swift:172`) and never removes entries. Every user of one project has the same
  storage key. On a server, unrelated requests then share one queue. Scope the queue to the
  storage instance. This is an internal fix.
- Each request builds an `AuthClient` with `CookieAuthStorage` and auto refresh `.manual`.
  `session()` refreshes an expired session within the request and writes the new cookies.
  This path is heavier than `scoped(accessToken:)`. Use it only for routes that need a session.

### 4.8 Webhook signatures

Auth Hooks use the Standard Webhooks scheme: HMAC-SHA256 over `id.timestamp.body`, with the
headers `webhook-id`, `webhook-timestamp`, and `webhook-signature`, and a `v1,whsec_…` secret.

```swift
public struct WebhookVerifier: Sendable {
  public init(secret: String, tolerance: Duration = .seconds(300))
  public func verify(headers: HTTPFields, body: some Collection<UInt8>) throws
}
```

- It uses `swift-crypto`, which is already a dependency, and a constant-time compare.
- It rejects timestamps outside the tolerance window, to stop replay.
- It lives in `Auth`, because Auth Hooks are the main user. Add typed payloads for each hook type
  (custom access token, send email, send SMS, MFA verification, password verification).

### 4.9 Lifecycle and observability

**Service lifecycle.** In `SupabaseNIO`, add `SupabaseService: Service` from
swift-service-lifecycle. It runs until graceful shutdown. Then it closes Realtime sockets with a
normal close frame, finishes any in-flight `httpSend`, and returns. Users add it to their
`ServiceGroup` next to their HTTP server.

**Tracing.** Most server frameworks use swift-distributed-tracing. Add a `DistributedTracing`
trait. It adds a middleware that starts a client span for each request and injects `traceparent`
from the current `ServiceContext`. The `OpenTelemetry` trait stays for current users. Q3 asks
whether to merge them later.

**Logging.** swift-log is already in place. Scoped clients take a `Logger`, so request metadata
(request ID, user ID) flows into SDK log lines. The SDK never logs tokens, cookies, or keys at any
level. Add a test that scans log output for these values.

**Metrics.** Out of scope for phase 1. Tracing spans cover most needs.

### 4.10 Storage on a server

Streaming and TUS already exist. Remaining work:

- Confirm that `URLSessionTransport` streams `HTTPBody` uploads on corelibs-foundation without full
  buffering. If it does not, document the NIO transport as required for large files.
- `ResumableStore` defaults to `.applicationSupportDirectory`. On Linux this resolves through the
  XDG variables and may not be writable in a container. The server preset turns the registry off
  or takes a directory (4.4).
- Add docs for the server patterns: a proxy download with the streamed body piped straight into
  the response, and signed upload URLs for direct browser uploads.

### 4.11 Realtime on a server

- `httpSend` already gives fire-and-forget broadcast with no socket. Add a top-level helper that
  does not need a channel object first, for example
  `supabase.realtime.broadcast(topic:event:payload:)`.
- Use `NIOWebSocketTransport` through the server preset (4.4).
- **Backpressure.** Today event streams buffer without a limit (`URLSessionWebSocketTransport.swift:289`
  and others). A slow server consumer then grows memory without a limit. Add a configurable
  buffering policy. The server preset uses a bounded buffer and drops the oldest events, with a
  logged warning and a counter.
- Reconnect with jitter. Many server instances that lose the socket at the same moment must not
  reconnect in lockstep.
- The lifecycle and network-path observers are Apple-only already. Add a test that no Apple-only
  observer starts on Linux.

### 4.12 Framework integrations

These are separate packages. They release on their own schedule and do not pull Vapor or
Hummingbird into the core package.

**`supabase-hummingbird`**

- A `SupabaseRequestContext` protocol that adds `supabase: SupabaseClient` (scoped) and
  `claims: VerifiedClaims?`.
- An `AuthMiddleware` that reads `Authorization: Bearer` or SSR cookies, verifies with
  `JWTVerifier`, and builds the scoped client.
- Response middleware that writes `CookieAuthStorage.responseCookies()`.

**`supabase-vapor`**

- `app.supabase` holds the shared client. `req.supabase` holds the scoped client.
- The same middleware shape as Hummingbird.
- `SupabaseService` registered with Vapor's lifecycle.

**Lambda sample.** A sample that uses `swift-aws-lambda-runtime`, `.server()`, and
`AsyncHTTPClientTransport`, built with the Static Linux SDK. Measure cold start and binary size.

Q1 decides who owns these packages.

### 4.13 Direct Postgres access (spike only)

Trusted backends often want SQL directly, not PostgREST. The typegen `@Table` macros already
describe tables and columns. A spike checks whether those descriptions can drive PostgresNIO
queries too. The spike ends with a written go or no-go decision. It ships no API.

### 4.14 CI, docs, and compliance

**CI**

- Linux integration tests against the Docker Supabase stack (`supabase start`), on the same matrix
  as the Linux unit tests.
- A Static Linux SDK build job: `swift build --swift-sdk x86_64-swift-linux-musl` with the `NIO`
  trait on.
- Run the transport conformance tests and benchmarks with the `NIO` trait on.

**Docs**

- A DocC article, "Using Supabase on the server": the server preset, scoped clients, the JWT
  verifier, cookies, webhooks, and service lifecycle.
- Update the README support matrix and `DEVELOPMENT.md`.

**Compliance**

- Add every new public symbol to `sdk-compliance.yaml` in the same commit, and run
  `./scripts/check-compliance.sh`.
- Compare against supabase-js server features (`@supabase/ssr`, `auth.getClaims`) and record
  any differences on purpose.

## 5. v3: breaking-change audit

Server support must land after v3 without a v4. So v3 must not ship a public shape that blocks a
section 4 feature. I checked each feature against the public API. A shape blocks a feature
when the feature needs a new protocol requirement, a new case in a public enum, a changed
signature, or a changed default.

### 5.1 Already server-ready in v3

These v3 changes are what make the rest additive. Keep them.

| v3 shape | Why it matters for servers |
|---|---|
| `ClientTransport` and `ClientMiddleware` use `HTTPTypes` and `HTTPBody` (V3_MIGRATION: "`ClientTransport` and `ClientMiddleware` replace `fetch:` closures") | `AsyncHTTPClientTransport` needs only a new conformance. |
| No `URLRequest`, `URLResponse`, `HTTPURLResponse`, or `URLSession` in the public API (V3_MIGRATION: "`HTTPResponse` replaces `HTTPURLResponse`") | A NIO build does not need `FoundationNetworking` in public signatures. |
| `WebSocketTransport` takes `URL` and `HTTPFields` | `NIOWebSocketTransport` needs only a new conformance. |
| `AuthStorage` is `async throws` | `CookieAuthStorage` conforms with no protocol change. |
| swift-log `Logger` in options (V3_MIGRATION: "swift-log replaces `SupabaseLogger`") | Scoped clients can take a per-request `Logger`. |
| Errors are structs with an extensible `Kind` | New error kinds (for example `.invalidConfiguration`) are additive. |
| SDK `async` functions run on the caller's executor | No hops to the main actor on a server. |
| `AutoRefreshPolicy.disabled` and `observesAppLifecycle` | The server preset only picks values. |
| `accessToken` option disables refresh and the auth-event task | It is the base for `scoped(accessToken:)`. |
| No process-wide mutable state in the public API | Many clients can live in one process. |

### 5.2 Decisions to settle before v3 ships

| ID | Shape | If we change it in v3 | If we keep it | Recommendation |
|---|---|---|---|---|
| D1 | `SupabaseClient.init`, `StorageClient.init(configuration:)`, and `FunctionsClient.init(configuration:)` trap on a bad URL (4.5) | One throwing initializer for each client. Matches supabase-js, which throws. Every call site adds `try`. Mobile apps that build the client in a global constant write `try!`, which still traps. Needs a CODE_STYLE.md update. | Add `init(validating:)` after v3. Two initializers forever. No churn for mobile users. | **Decided: change it in v3.** One initializer per client, and parity with supabase-js. |
| D2 | `HTTPBody.Element` is `ArraySlice<UInt8>` | Use `ByteBuffer` to avoid one copy per chunk in NIO. That forces a swift-nio dependency on every user. | One copy per chunk in the NIO transport. swift-openapi-runtime makes the same choice. | **Keep.** The copy is small next to network cost. |
| D3 | `WebSocketConnection.events` is an `AsyncStream` with no backpressure | Use a pull-based `receive()` so the transport stops reading when the consumer is slow. | The Realtime core drains the stream at once. Slow consumers sit behind the public channel streams, and a buffering option there is additive (4.11). | **Keep.** Bound memory at the public channel streams. |
| D4 | `WebSocketFrame` and `WebSocketEvent` are public enums | Adding a case later (for example `ping`) breaks exhaustive switches. | Servers need no new case. NIO handles ping and pong inside the transport. | **Keep.** |
| D5 | The stored session format (`PersistedSession`, schema 1) | — | It writes snake_case fields that supabase-js can read, plus `schema` and `received_at`. The codec already reads the bare snake_case session that supabase-js writes (`PersistedSessionCodec`, `.v2SnakeCase`). | **Keep.** Before v3 ships, add a round-trip test with a session JSON that supabase-js wrote. Schema 1 then cannot drift from what cookies need. Not a breaking change. |

### 5.3 What v3 needs to include

- **Required:** nothing.
- **D1:** throwing initializers for `SupabaseClient`, `StorageClient`, and `FunctionsClient`,
  plus `SupabaseClientError` and the `.invalidConfiguration` kinds, a CODE_STYLE.md update,
  migration guide entries, and `sdk-compliance.yaml` updates.
- **Recommended, not breaking:** the D5 round-trip test, and the `StorageRequests.swift:63` fix
  (4.5).

Everything else in section 4 is additive and ships after v3.

## 6. Phases (after v3)

### Phase 1: Foundation

Covers 4.1, 4.2, 4.3, 4.4, and the CI part of 4.14. (4.5 ships in v3.)

Done when:

- A Vapor or Hummingbird sample serves authenticated PostgREST requests on Linux through
  `scoped(accessToken:)` and `AsyncHTTPClientTransport`.
- No `preconditionFailure` remains on a runtime-input path.
- Linux integration tests pass in CI.
- `DEVELOPMENT.md` lists Linux as supported.

### Phase 2: Server auth and operations

Covers 4.6, 4.7, 4.8, 4.9, 4.10, and 4.11.

Done when:

- A Swift API and a Next.js app that uses `@supabase/ssr` share one login (golden tests pass).
- An Auth Hook handler verifies signatures.
- `SupabaseService` shuts down cleanly in a `ServiceGroup`.
- Realtime memory stays bounded under a slow-consumer test.

### Phase 3: Ecosystem

Covers 4.12, 4.13, and the docs part of 4.14.

Done when:

- `supabase-vapor` and `supabase-hummingbird` have a first release.
- The Lambda sample is published with cold-start numbers.
- The Postgres spike has a written decision.

## 7. Open questions

- **Q1. Who owns the integrations?** Options: Supabase-owned packages under `supabase/`,
  or community-owned under `supabase-community/` with Supabase review. Ownership sets the support
  promise and the release process.
- **Q2. Which WebSocket client?** Options:
  - `swift-websocket` from the Hummingbird project: async/await native, with compression.
  - `websocket-kit` from Vapor: mature, but older API.
  - Raw `NIOWebSocket`: no new dependency, but more code to own.
  Leaning toward `swift-websocket`. Confirm its TLS and proxy support first.
- **Q3. One tracing trait or two?** Keep `OpenTelemetry` and add `DistributedTracing`, or move to
  `DistributedTracing` only and bridge to OpenTelemetry through `swift-otel`.
- **Q4. How do we pin the cookie format?** Read the `@supabase/ssr` source at a pinned version.
  Generate fixtures from a small Node script in CI, so drift fails a test.
- **Q5. Do trait-disabled dependencies still get fetched?** Check whether SwiftPM 6.2 resolves and
  fetches dependencies used only by a disabled trait. If it does, iOS users pay a resolve-time cost
  for `async-http-client`. The fallback is a separate package, `supabase-swift-nio`.
- **Q6. Is `JWTVerifier` its own product?** Middleware-only users may want it without the full
  `Supabase` product. It could live in `Auth`, or in a small `SupabaseJWT` product.

## 8. Risks

| Risk | Mitigation |
|---|---|
| The scoped-client refactor changes behavior for mobile users | Scoped clients use a separate internal path. The main `init` does not change. Run the full Auth suite plus the main-actor call-site tests. |
| v3 ships a shape this audit missed | Re-run the section 5 audit on the v3 release candidate |
| Cookie format drift from `@supabase/ssr` | Generated fixtures in CI (Q4) |
| Two transports double the test surface | One shared conformance suite that runs against every transport |
| Server users hit unbounded Realtime buffers before phase 2 | Document the risk in the phase 1 release notes |
| Maintainers lack time for framework packages | Settle Q1 before phase 3 starts |
