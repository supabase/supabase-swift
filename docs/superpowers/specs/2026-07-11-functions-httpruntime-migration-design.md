# Functions → HTTPRuntime migration design

## Goal

Migrate `Sources/Functions`'s internal HTTP plumbing from `Helpers.HTTPClient`/`Helpers.HTTPRequest`/`Helpers.HTTPResponse` (plus a hand-rolled `URLSession`+delegate for streaming) to the new `HTTPRuntime` target, without changing `FunctionsClient`'s public API in any way.

`HTTPRuntime` was originally built for a codegen pipeline (see `docs/superpowers/specs/2026-07-11-http-runtime-test-helpers-design.md`); this is its first adoption by a hand-written client. No other module (Auth, PostgREST, Storage, Realtime, Supabase) uses it yet.

## Non-goals

- No public API changes to `FunctionsClient`: the `FetchHandler` typealias (`(URLRequest) async throws -> (Data, URLResponse)`), both public initializers, `invoke`/`invoke(decode:)`/`invoke(decoder:)`, `_invokeWithStreamedResponse`, `setAuth`, and every `FunctionsError` case stay exactly as they are today.
- No promotion of `HTTPRuntime` from `package` to `public` access — this migration is entirely internal to the `Functions` target.
- No test-framework migration. `Tests/FunctionsTests` stays on XCTest + Mocker; adopting Swift Testing / `HTTPRuntimeTestHelpers` for this module is the separate SDK-435 migration track, out of scope here.
- No new multipart/file-upload support in Functions — it doesn't use it today and doesn't need it.
- No SSE/event-stream framing — Functions' streaming already yields raw `Data` chunks (no SSE parsing), which is exactly what `HTTPRuntime.HTTPTransport.stream(_:)` already provides.
- No changes to `Sources/Helpers` — `HTTPClientType`/`HTTPClient`/`LoggerInterceptor`/`Helpers.HTTPRequest`/`Helpers.HTTPResponse` stay exactly as they are, since Auth, PostgREST, Realtime, and Storage all still depend on them. Functions simply stops calling them; nothing about them changes.
- **Request/response logging is dropped for now, to be revisited later.** `LoggerInterceptor`'s verbose request/response logging (see "Current state" below) is not reimplemented against `HTTPRuntime` types in this migration. The public `logger:` initializer parameter stays (no public API change), but it becomes inert — supplying a logger no longer produces any log output. This is a deliberate, temporary regression, not an oversight; re-adding equivalent logging directly against `HTTPRuntime.HTTPRequest`/`HTTPResponse` is follow-up work, not part of this migration.

## Current state (for reference)

- `FunctionsClient.invoke*` builds a `Helpers.HTTPRequest`, sends it via `any HTTPClientType` (`Helpers.HTTPClient`, an actor wrapping the stored `fetch:` closure with an interceptor chain), gets back a `Helpers.HTTPResponse`.
- `_invokeWithStreamedResponse` bypasses the `fetch:` closure entirely: it builds its own `URLSession(configuration: sessionConfiguration)` and a custom `URLSessionDataDelegate` (`StreamResponseDelegate`) that yields `Data` chunks into an `AsyncThrowingStream<Data, any Error>`.
- Headers are built/merged as `HTTPTypes.HTTPFields` in `Types.swift` and `FunctionsClient.swift`.
- `Functions`'s `Package.swift` dependencies: `ConcurrencyExtras`, `HTTPTypes`, `Helpers`.

## Architecture

### Buffered path (`invoke`, `invoke(decode:)`, `invoke(decoder:)`)

A new private type, `FetchHandlerTransport`, adapts the stored `fetch: FetchHandler` closure to `HTTPRuntime.HTTPTransport`. Logging is intentionally not reimplemented here (see Non-goals) — `Helpers.HTTPClient`'s interceptor chain is not carried over at all; the adapter is a plain, direct pass-through:

```swift
private struct FetchHandlerTransport: HTTPTransport {
  let fetch: FunctionsClient.FetchHandler

  func send(_ request: HTTPRequest, uploadProgress: ProgressHandler?) async throws(HTTPError) -> HTTPResponse {
    let urlRequest = Self.makeURLRequest(request)
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await fetch(urlRequest)
    } catch {
      throw HTTPError.transport(error)
    }
    guard let http = response as? HTTPURLResponse else {
      throw HTTPError.transport(URLError(.badServerResponse))
    }
    var headers: [String: String] = [:]
    for (key, value) in http.allHeaderFields {
      if let key = key as? String, let value = value as? String { headers[key] = value }
    }
    return HTTPResponse(head: HTTPResponseHead(status: http.statusCode, headers: headers), body: data)
  }

  func stream(_ request: HTTPRequest) async throws(HTTPError) -> HTTPResponseStream {
    // Never called — FunctionsClient always uses URLSessionTransport directly for streaming.
    fatalError("FetchHandlerTransport does not support streaming; use URLSessionTransport instead")
  }
}
```

`invoke`/`invoke(decode:)`/`invoke(decoder:)` build an `HTTPRuntime.HTTPRequest` (method, url, headers as `[String: String]`, body as `.data(Data)`) instead of `Helpers.HTTPRequest`, construct a `FetchHandlerTransport(fetch: fetch)`, and call `.send(request, uploadProgress: nil)`. The existing status-check/error-mapping logic (non-2xx → `FunctionsError.httpError(code:data:)`, relay-error response header → `.relayError`) moves to operate on the returned `HTTPResponse` instead of `Helpers.HTTPResponse` — same checks, same error cases, different input type. The `logger:` initializer parameter is still accepted (public API unchanged) but is no longer passed anywhere or used — `FunctionsClient` doesn't need to store it.

### Streaming path (`_invokeWithStreamedResponse`)

Replaces the custom `URLSession` + `StreamResponseDelegate` (`FunctionsClient.swift:317-359`, deleted entirely) with `HTTPRuntime.URLSessionTransport(configuration: sessionConfiguration)`, built directly (same `sessionConfiguration` stored property already used today) — not through `FetchHandlerTransport`, since streaming never went through the public `fetch:` closure to begin with and continues not to.

```swift
let transport = URLSessionTransport(configuration: sessionConfiguration)
let responseStream = try await transport.stream(request)
// same head-status-check as today (relay-error / non-2xx), then yield responseStream.body's chunks
```

### Headers

`HTTPTypes.HTTPFields` usage in `Types.swift` (`FunctionInvokeOptions.headers`) and `FunctionsClient.swift` (header merging) is replaced with plain `[String: String]` dictionary merging, matching `HTTPRuntime.HTTPRequest.headers`'s shape. The `HTTPTypes` dependency is dropped from the `Functions` target in `Package.swift`.

### Errors

`FunctionsError`'s two cases (`.relayError`, `.httpError(code:data:)`) are unchanged. `HTTPError` (from `HTTPRuntime`) never leaks to `FunctionsClient` callers — any transport-level failure inside `FetchHandlerTransport.send` or the streaming path's `URLSessionTransport.stream` call is caught and re-thrown as whatever `FunctionsError`/underlying error the current code already throws in that situation (i.e. the conversion layer absorbs `HTTPError`, it doesn't propagate it).

### Package.swift

```
Functions target dependencies: ConcurrencyExtras, Helpers, HTTPRuntime   // HTTPTypes removed
```

## Data flow

1. Caller invokes `client.invoke(...)`.
2. `FunctionsClient` builds an `HTTPRuntime.HTTPRequest` from the function name, `FunctionInvokeOptions`, base URL, and current headers/auth.
3. For the buffered path: wraps the stored `fetch:` closure in `FetchHandlerTransport`, calls `.send(_:)`, gets `HTTPResponse`, applies existing status/error checks, decodes/returns the body exactly as today.
4. For the streaming path: builds `URLSessionTransport(configuration: sessionConfiguration)` directly, calls `.stream(_:)`, gets `HTTPResponseStream` (head + `AsyncThrowingStream<Data, any Error>`), applies the same head-status-check before yielding chunks to the caller.

## Testing

`Tests/FunctionsTests` (XCTest + Mocker, `URLProtocol`-level interception, `InlineSnapshotTesting` curl-snapshot assertions in `RequestTests.swift` and `FunctionsClientTests.swift`) is the correctness oracle for this migration and must keep passing **without changing its own mocking mechanism** — Mocker intercepts at the `URLSession`/`URLProtocol` level, which sits below `FetchHandlerTransport`'s conversion layer and is unaffected by it, since the adapter still calls the real `fetch:` closure with a real `URLRequest`.

If the `HTTPRequest ↔ URLRequest` round-trip introduces any incidental difference from today's `Helpers.HTTPRequest ↔ URLRequest` conversion (header key casing, query-item ordering, body encoding) that changes a recorded curl snapshot, that is a real regression in the adapter to fix — re-recording a snapshot is only acceptable when the difference is deliberate and reviewed, never as a way to make a mismatch disappear.

No new tests are required by this migration beyond what's needed to keep the existing suite green; this is an internal refactor, not new behavior.

## Error handling

- Transport-level failures (network errors, decoding failures) from `FetchHandlerTransport.send` or `URLSessionTransport.stream` are caught at the `HTTPError.transport(any Error)` boundary and converted to whatever error `FunctionsClient` already surfaces for that failure mode today (this migration doesn't change what errors callers see, only what's happening internally to produce them).
- Non-2xx responses and the relay-error header check keep their exact current semantics, just reading from `HTTPResponse`/`HTTPResponseHead` instead of `Helpers.HTTPResponse`.
