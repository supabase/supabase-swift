# Architecture

This is the official Supabase SDK for Swift, mirroring the design of supabase-js.

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

## Dependencies

### Core Dependencies

- `swift-crypto`: Cryptographic operations
- `swift-http-types`: Modern HTTP types
- `swift-clocks`: Time-based operations
- `swift-concurrency-extras`: Concurrency utilities

### Test Dependencies

- `swift-snapshot-testing`: Snapshot testing
- `swift-custom-dump`: Better test output
- `swift-issue-reporting` (Swift 6.4+) / `xctest-dynamic-overlay` (earlier toolchains): test
  utilities and issue reporting
- `Mocker`: URL mocking

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

