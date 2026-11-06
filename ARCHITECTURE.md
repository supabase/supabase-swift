# Architecture

This is the official Supabase SDK for Swift, mirroring the design of supabase-js.

## Project Structure

- `Sources/`: Source code organized by module
  - `Auth/`: Authentication module
  - `Functions/`: Edge Functions client
  - `PostgREST/`: Database client
  - `PostgrestMacros/`: The `@Table` macros. An opt-in product: `Supabase` does not re-export
    it, so only apps that `import PostgrestMacros` compile swift-syntax
  - `PostgrestMacrosPlugin/`: The compiler plugin that implements the macros
  - `Realtime/`: Realtime subscriptions
  - `Storage/`: File storage client
  - `Supabase/`: Main client that integrates all modules
  - `Helpers/`: Shared utilities, including the HTTP layer
  - `TestHelpers/`: Test utilities
- `Tests/`: Unit and integration tests organized by module, plus:
  - `CompileFailures/`: Fixtures that must fail to compile
    (`./scripts/check-compile-failures.sh`)
  - `SupabaseTypegen*OutputTests/`: Compile and run code from `supabase-typegen` (see
    [tools/supabase-typegen/README.md](tools/supabase-typegen/README.md))
- `Examples/`: Example applications demonstrating SDK usage
- `tools/`: `supabase-typegen` (a separate SwiftPM package) and the Node tooling for spell checks
- `docs/migrations/`: Migration guides. `docs/migrations/v<N>/` holds one file per module for major version `<N>`; the root `V<N>_MIGRATION.md` is its overview

## Dependencies

[`Package.swift`](Package.swift) lists the dependencies and says which target uses each one. It
serves Swift 6.4+, and [`Package@swift-6.2.swift`](Package@swift-6.2.swift) serves earlier
toolchains. Keep the two in sync.

## Architecture Notes

### Client Initialization

The main `SupabaseClient` acts as a facade for all sub-clients (Auth, Database, Storage, Functions, Realtime). Each sub-client can also be used independently, with `init(configuration:)`. CODE_STYLE.md "Client Configuration" sets the shape of every configuration type.

### Async/Await

The SDK is fully async/await based. Avoid using completion handlers in new code.

- A public call that changes client state is `async` and returns once the change has taken effect. A caller who does not want to wait wraps it in a `Task`.
- Every async API returns promptly when its task is cancelled, and it throws `CancellationError` (see CODE_STYLE.md "The error model").
- Observation uses streams, not callbacks (see CODE_STYLE.md "Streams and Events").

### Concurrency

- Stateful public clients are an `actor` or a `final class: Sendable`. Mutable state sits behind `LockIsolated` or an internal actor. Do not add `NSLock`, `Mutex`, or Combine.
- Use `@unchecked Sendable` only for a Foundation bridge, with a comment that says why.
- Mark blocking I/O `@concurrent`. Decode user types on the caller's actor, so isolated conformances work.
- Name every long-lived task `supabase.<module>.<role>`.
- Helpers owns one app-lifecycle observer. Each module maps its events to its own policy, and the setting is `observesAppLifecycle`.

### Sendable Conformance

All public types should conform to `Sendable` where appropriate for Swift 6 compatibility.

### Access Control

- Every client module (Auth, Functions, PostgREST, Realtime, Storage) has `@_exported import Helpers`, so every public Helpers type shows up through each of them. Helpers' public surface holds only types that two or more modules use in public signatures: the HTTP layer, `JSONValue`, `SupabaseError`, `HTTPErrorResponse`, and `PageSequence`. A type that belongs to one module lives in that module.
- Use `package` only for something another SDK module needs. Tests use `@testable import`.
- `@_spi(Experimental)` is the only SPI name.

### HTTP Layer

Uses modern `HTTPTypes` for request/response handling. Every module shares one public seam: a `ClientTransport` performs the exchange and an ordered `ClientMiddleware` chain runs in front of it, grouped into one `HTTPClientConfiguration` that every client takes as a single `http:` parameter, so a custom networking stack, extra headers, or a test stub can be injected once for the whole SDK.

**Chain.** Every client builds its `HTTPClient` the same way. The order, outermost first: retry, user middlewares, SDK middlewares (trace context, then the facade's Auth middleware), logger, transport. No module reads the access token outside this chain, so every retry gets a fresh token.

**Headers.** Each request starts from the module's configured headers. These always include `X-Client-Info`, built by one Helpers function, and `apikey`, from the shared `HTTPField.Name.apikey`. A per-call header wins over a configured header, and a configured header wins over an SDK default. A static `Authorization` header wins over any token middleware in every module.

**Access token.** Middleware is the one way to put a token on an HTTP request. HTTP modules have no `accessToken` setting. A standalone client gets a token from an `AccessTokenMiddleware` that the caller adds to `http.middlewares`. Through the facade, the SDK adds its Auth middleware instead. Both run inside the retry. A provider failure is `<Module>Error(kind: .accessToken)` in every module, standalone and through the facade. Realtime is the one exception: the socket needs the token outside any HTTP request (join, token refresh), so `RealtimeClient.Configuration.accessToken` is its only token source, and `httpSend` uses it too. Do not add `AccessTokenMiddleware` to Realtime's `http`.

**Retries.** Only `retryEnabled` turns retry on or off. Every retry goes through `RetryRequestInterceptor` on the injected clock. Each module's policy (statuses, methods, attempts) is listed in one table in this file. A 429 is retried only with `Retry-After`, the same way in every module that retries.

**Timeouts.** A parameter named `timeout` always means the idle timeout, as in `URLRequest.timeoutInterval`, and a timeout fails as `.transport`. A total deadline needs a different name.

**Errors and cancellation.** `HTTPClient` maps a cancelled task to `CancellationError`, for the response head and the body. It keeps at most the first 1 MiB of a non-2xx body. Modules map only the remaining `URLError`s to `<Module>Error(kind: .transport)`.

### Logging

- Every SDK logger comes from `supabaseDefaultLogger(label: "io.supabase.<module>")`, and the configuration init sets the `system` metadata. The logger is non-optional.
- A redacting handler in Helpers wraps every SDK logger when the client is created. It removes JWTs, URL query strings and fragments, and secret JSON keys (tokens, passwords, signed URLs). This is the target; SDK-2876 tracks it. Today only Auth redacts, and only in `Configuration.init`, so a logger set on the configuration after init is not wrapped.
- HTTP traffic logs at `.trace`. At `.error`, log an SDK-written summary, never a raw `URLError` or a message that can carry a token.

### Configuration

The facade takes one `SupabaseClient.Configuration`, with one nested type per sub-client and `Global` for shared settings. Client setup types end in `Configuration`; `Options` is only for per-call settings (see CODE_STYLE.md "Client Configuration"). Every module client has the same shape: a nested `Configuration` that holds `url`, a public `configuration` property, and `init(configuration:)` as the only init.

```swift
SupabaseClient(
  supabaseURL: url,
  supabaseKey: key,
  configuration: SupabaseClient.Configuration(
    database: .init(...),
    auth: .init(...),
    global: .init(...)
  )
)
```

The facade passes shared settings down the same way to every sub-client:

- Each nested sub-client configuration can override `http`, `logger`, and `clock`. The facade uses the module value if it is set, otherwise the global one.
- One helper merges the HTTP stack for all five sub-clients: the override transport, then the global middlewares, then the module middlewares, then the SDK middlewares.
- A per-module value wins over a global value. The facade never drops or overwrites a value the user set.
