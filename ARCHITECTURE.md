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

The main `SupabaseClient` acts as a facade for all sub-clients (Auth, Database, Storage, Functions, Realtime). Each sub-client can also be used independently.

### Async/Await

The SDK is fully async/await based. Avoid using completion handlers in new code.

### Sendable Conformance

All public types should conform to `Sendable` where appropriate for Swift 6 compatibility.

### HTTP Layer

Uses modern `HTTPTypes` for request/response handling. Every module shares one public seam: a `ClientTransport` performs the exchange and an ordered `ClientMiddleware` chain runs in front of it, grouped into one `HTTPClientConfiguration` that every client takes as a single `http:` parameter, so a custom networking stack, extra headers, or a test stub can be injected once for the whole SDK.

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

