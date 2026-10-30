# V3 migration guide

This guide moves an app from supabase-swift v2 (`2.55.4`) to v3. This file covers the changes
that apply to every module and to `SupabaseClient`; each module has its own file for the rest.

> [!NOTE]
> v3 is in prerelease (alpha). The Auth API can still change before the final release.

## How to migrate

1. Install Xcode 26.0 or later (Swift 6.2 or later).
2. Update the package requirement:

   ```swift
   .package(url: "https://github.com/supabase/supabase-swift", from: "3.0.0-alpha.1")
   ```

3. Build. Expect many compile errors.
4. Fix the errors in [Changes in every module](#changes-in-every-module) and
   [SupabaseClient](#supabaseclient) first. Then fix the errors one module at a time with the
   [module guides](#module-guides). Use the "Renames and type changes" table in each file first;
   most errors are a rename.
5. Read every "Silent changes" list, in this file and in each module guide you use. These
   changes compile but behave differently. Search your code for each one.
6. Run your tests and test the app by hand.

## Module guides

| Module | Guide | Status |
| --- | --- | --- |
| Auth | [Auth.md](docs/migrations/v3/Auth.md) | still changing |
| PostgREST | [PostgREST.md](docs/migrations/v3/PostgREST.md) | ready for feedback |
| Storage | [Storage.md](docs/migrations/v3/Storage.md) | ready for feedback |
| Functions | [Functions.md](docs/migrations/v3/Functions.md) | ready for feedback |
| Realtime | [Realtime.md](docs/migrations/v3/Realtime.md) | ready for feedback |

## Changes in every module

### Silent changes

Changes that still compile but behave differently. Check each one by hand.

- **Debug builds log by default.** If you pass no `logger:`, debug builds now log warnings and
  errors to stderr. Release builds stay silent. See [Logging](#logging-swift-log-replaces-supabaselogger).
- **Network and decoding errors are wrapped.** A `URLError` or `DecodingError` no longer reaches
  you as itself. It arrives as the module error (`AuthError`, `PostgrestError`, `StorageError`,
  `FunctionsError`, `RealtimeError`) with the original in `underlyingError`. Search for
  `as URLError`, `as? URLError`, `as DecodingError` and `as? DecodingError` near SDK calls.
- **Cancellation throws `CancellationError`.** A cancelled task now throws `CancellationError`
  in every module, also where v2 threw `URLError(.cancelled)`. Replace
  `catch let error as URLError where error.code == .cancelled` with `catch is CancellationError`.
- **SDK `async` functions run on the caller's executor.** Called from `@MainActor` code, the SDK
  now decodes responses on the main actor. If large responses stall the UI, call the SDK from a
  `@concurrent` function. See [Caller's executor](#sdk-async-functions-run-on-the-callers-executor).
- **Middlewares and transports run once per attempt.** Auth, PostgREST and Storage reads retry
  through one shared policy with jittered backoff, and they honor `Retry-After`. Each retry runs
  your `ClientMiddleware` and `ClientTransport` again. Storage reads now retry (pass
  `retryEnabled: false` to stop it). PostgREST no longer retries an error that your own transport,
  middleware or `accessToken` closure throws.
- **Timeouts come from the SDK.** The SDK sets the request timeout itself: 60 seconds, or
  150 seconds for Functions. `URLSessionConfiguration.timeoutIntervalForRequest` has no effect on
  SDK requests. Set `HTTPClientConfiguration(timeout:)` instead.
- **No redirect for a one-shot body.** On Apple platforms, `URLSessionTransport` returns a 307 or
  308 response instead of following it when the request body is
  `HTTPBody(_:length:iterationBehavior: .single)`. A `.single` body with `length: .known(n)` must
  yield exactly `n` bytes, or the request fails with `HTTPBodyLengthMismatchError`. Search for
  `iterationBehavior: .single`.

### Renames and type changes

| v2 | v3 |
| --- | --- |
| `AnyJSON` | `JSONValue` |
| `SupabaseLogger`, `SupabaseLogMessage`, `SupabaseLogLevel`, `OSLogSupabaseLogger` | `Logging.Logger` from swift-log |
| `AuthClient.FetchHandler`, `PostgrestClient.FetchHandler`, `FunctionsClient.FetchHandler` | `any ClientTransport` |
| `StorageHTTPSession` | `any ClientTransport` |
| `fetch:` argument on `AuthClient`, `AuthClient.Configuration`, `PostgrestClient`, `PostgrestClient.Configuration`, `FunctionsClient`, `RealtimeClientOptions` | `http: HTTPClientConfiguration` |
| `StorageClientConfiguration(session:)` | `StorageClientConfiguration(http:)` |
| `HTTPURLResponse` in public signatures (for example `PostgrestResponse.response`) | `HTTPResponse` (swift-http-types) |
| `HTTPError` | the module error, with `response: HTTPErrorResponse?` |

Naming rules applied across all modules (the module tables list each symbol):

- A method that only reads a value drops its `get` prefix: `getPublicURL` is `publicURL`.
- An argument that names an identifier is `id:`: `deleteClient(clientId:)` is
  `deleteClient(id:)`.
- A Boolean property reads as an assertion: `useNewHostname` is `usesNewHostname`.
- Enum-like values with an open set of cases are structs. A `switch` over one needs `default:`.

### Minimum toolchain: Xcode 26 and Swift 6.2

v3 needs Xcode 26.0 or later and Swift 6.2 or later. v2 needed Xcode 16.4 and Swift 6.1. No
source change is needed for this item.

### All deprecated APIs are removed

Every API that was `@available(*, deprecated)` in v2.55.4 is gone. If your v2 build showed a
deprecation warning, use the replacement that the warning named. Each module guide lists its
removed APIs.

### Logging: swift-log replaces `SupabaseLogger`

Every `logger:` parameter now takes a `Logging.Logger`. The SDK does not re-export `Logging`, so
add `swift-log` to your package and `import Logging` where you build the logger.

```swift
// Package.swift
.package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
.product(name: "Logging", package: "swift-log"),

// v2
let client = SupabaseClient(
  supabaseURL: url, supabaseKey: key,
  options: .init(global: .init(logger: MyCustomLogger()))
)

// v3
import Logging

var logger = Logger(label: "myapp")
logger.logLevel = .debug
let client = SupabaseClient(
  supabaseURL: url, supabaseKey: key,
  options: .init(global: .init(logger: logger))
)
```

To silence the debug-build default, pass
`Logger(label: "myapp") { _ in SwiftLogNoOpLogHandler() }`.

#### OSLog parity

The SDK ships no replacement for `OSLogSupabaseLogger`. Write a small `LogHandler` that wraps an
`os.Logger` and maps each `Logging.Logger.Level` to an OSLog level. Set its default `logLevel` to
`.trace` to forward every message, as v2 did. Then pass
`Logger(label: "myapp") { MyOSLogHandler(label: $0) }`. If one file imports both `Logging` and
`OSLog`, write `os.Logger` or `Logging.Logger` to remove the ambiguity.

### `ClientTransport` and `ClientMiddleware` replace `fetch:` closures

Every client sends requests through one `ClientTransport` behind an ordered list of
`ClientMiddleware`. Both go in one `HTTPClientConfiguration`, passed as `http:`.
`URLSessionTransport(session:)` wraps the `URLSession` you used in v2.

```swift
// v2
let database = PostgrestClient(url: databaseURL, fetch: { try await session.data(for: $0) })
let storage = SupabaseStorageClient(
  configuration: StorageClientConfiguration(
    url: storageURL, headers: headers, session: StorageHTTPSession(session: session)
  )
)

// v3
let http = HTTPClientConfiguration(transport: URLSessionTransport(session: session))
let database = PostgrestClient(url: databaseURL, http: http)
let storage = StorageClient(
  configuration: StorageClientConfiguration(url: storageURL, headers: headers, http: http)
)
```

A middleware must spell `next` with `nonisolated(nonsending)`, or it does not conform:

```swift
struct AppVersionMiddleware: ClientMiddleware {
  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    next: nonisolated(nonsending) @Sendable (HTTPRequest, HTTPBody?) async throws
      -> (HTTPResponse, HTTPBody?)
  ) async throws -> (HTTPResponse, HTTPBody?) {
    var request = request
    request.headerFields[HTTPField.Name("X-App-Version")!] = "2.1.0"
    return try await next(request, body)
  }
}
```

Middlewares run in array order on the way out and in reverse order on the way back. A middleware
that retries must not retry a body whose `iterationBehavior` is `.single`. `import Supabase` also
brings in the `HTTPTypes` names (`HTTPRequest`, `HTTPResponse`, `HTTPFields`). If another library
exports the same names, write `HTTPTypes.HTTPRequest`.

### `HTTPResponse` replaces `HTTPURLResponse`

`HTTPResponse` has `status` and `headerFields`. It has no URL.

```swift
// v2
let etag = response.response.value(forHTTPHeaderField: "ETag")
let code = response.response.statusCode

// v3
let etag = response.response.headerFields[.eTag]
let code = response.response.status.code
```

If a dependency needs an `HTTPURLResponse`, use the failable
`HTTPURLResponse(httpResponse:url:)`.

### `HTTPError` is removed

Each module error conforms to `SupabaseError`. It carries `response: HTTPErrorResponse?` (status
code, `HTTPFields` headers, raw body, `requestID`) and `underlyingError`. A body that is not the
module's error format gives kind `.server` with no `serverError`.

```swift
// v2
} catch let error as HTTPError {
  print(error.response.statusCode, String(decoding: error.data, as: UTF8.self))
}
} catch let error as URLError where error.code == .notConnectedToInternet {
  showOfflineBanner()
}

// v3
} catch let error as any SupabaseError {
  if let response = error.response {
    print(response.statusCode, String(decoding: response.body, as: UTF8.self))
  } else if (error.underlyingError as? URLError)?.code == .notConnectedToInternet {
    showOfflineBanner()
  }
}
```

Errors that your own transport, middleware or `accessToken` closure throws are not wrapped.

### SDK `async` functions run on the caller's executor

All SDK targets build with `NonisolatedNonsendingByDefault` (SE-0461). An SDK `async` method
called from the main actor stays on the main actor. Move heavy decoding off it with
`@concurrent`:

```swift
// v3
@concurrent func fetchTodos() async throws -> [Todo] {
  try await client.from("todos").select().execute().value
}

@MainActor func load() async throws {
  rows = try await fetchTodos()
}
```

`@concurrent` needs a nonisolated `Decodable` conformance on `Todo`.

## SupabaseClient

### Silent changes

Changes that still compile but behave differently. Check each one by hand.

- **Your `Authorization` header wins.** PostgREST, Storage and Functions set `Authorization`
  only when the request does not have one. In v2, the session token replaced a header that you
  set with `setHeader`. Search for `Authorization` set on a builder, a Storage `setHeader`, or
  `FunctionInvokeOptions.headers`. A middleware in `GlobalOptions.http.middlewares` no longer
  sees `Authorization` on these requests; read it in a `ClientTransport`.
- **Access-token errors fail the request.** If the session refresh or your
  `AuthOptions.accessToken` closure throws, the request now fails with that error. In v2 the
  request went out with the API key. Only a missing session still falls back to the key. A
  refresh the server rejects fails the request with an `AuthError` of kind `.sessionInvalidated`.
- **Realtime uses the global logger when you pass none.** `SupabaseClient` keeps a `logger`
  you set in `SupabaseClientOptions(realtime:)`. With `nil`, the default, it uses
  `GlobalOptions.logger`.
- **Auth events do not build the Realtime client.** `SupabaseClient` pushes a new token only to
  a Realtime client that already exists. A client built later fetches the current token itself.
- **Realtime does not get the global `URLSession`.** If the WebSocket needs it (for example
  for certificate pinning), pass `RealtimeClientOptions(webSocketTransport:)` a
  `URLSessionWebSocketTransport` built from the session.
- **`supabase.functions` is cached.** Each access returns the same client. The default
  `FunctionsOptions` decoder changed; see [Functions.md](docs/migrations/v3/Functions.md).

### Renames and type changes

| v2 | v3 |
| --- | --- |
| `supabase.database` | `supabase.from(_:)`, `supabase.rpc(_:)`, `supabase.schema(_:)` |
| `supabase.realtimeV2` | `supabase.realtime`; see [Realtime.md](docs/migrations/v3/Realtime.md) |
| `supabase.channel(_:options:)` | `supabase.channel(_:configure:)` |
| `supabase.storage: SupabaseStorageClient` | `supabase.storage: StorageClient` |
| `GlobalOptions(session:)` | `GlobalOptions(http: .init(transport: URLSessionTransport(session:)))` |
| `GlobalOptions.logger: (any SupabaseLogger)?` | `GlobalOptions.logger: Logging.Logger` |
| `AuthOptions.autoRefreshToken: Bool` | `AuthOptions.autoRefresh: AuthClient.AutoRefreshPolicy`; see [Auth.md](docs/migrations/v3/Auth.md) |
| `AuthOptions(encoder:decoder:)` | removed |
| `AuthOptions(emitLocalSessionAsInitialSession:)` | removed; see [Auth.md](docs/migrations/v3/Auth.md) |
| `StorageOptions.useNewHostname` | `StorageOptions.usesNewHostname` |
| `FunctionsOptions.region: String?` | `FunctionsOptions.region: FunctionRegion?` |

### `GlobalOptions.session` is removed

Configure the `URLSession` on the transport. One `http` value covers every sub-client.

```swift
// v2
options: .init(global: .init(session: mySession))

// v3
options: .init(
  global: .init(http: .init(transport: URLSessionTransport(session: mySession))),
  // Only if the WebSocket needs the session:
  realtime: .init(
    webSocketTransport: URLSessionWebSocketTransport(
      configuration: mySession.configuration, delegate: mySession.delegate
    )
  )
)
```

### `FunctionsOptions` takes a `FunctionRegion`

The `String?` initializer is removed. A string literal still compiles; a `String` variable needs
a conversion. `FunctionsOptions` also gains `http` and `logger`; `nil` means the global value.

```swift
// v2
let options = SupabaseClientOptions(functions: .init(region: settings.functionsRegion))

// v3
let options = SupabaseClientOptions(
  functions: .init(region: FunctionRegion(rawValue: settings.functionsRegion))
)
```
