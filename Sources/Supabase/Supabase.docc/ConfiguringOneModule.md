# Configuring One Module

Change the HTTP behavior or the logs of one sub-client with the global settings.

## Overview

``SupabaseClient/Configuration`` has one `http` setting and one `logger`, in
``SupabaseClient/Configuration/Global``. Every sub-client sends through the same transport and
middlewares, and logs to the same logger. To treat one sub-client differently, look at the
request path or at the log metadata.

| Sub-client | Request path prefix | `system` log metadata |
| --- | --- | --- |
| Auth | `/auth/v1/` | `auth` |
| Database | `/rest/v1/` | `postgrest` |
| Storage | `/storage/v1/` | `storage` |
| Edge Functions | `/functions/v1/` | `functions` |
| Realtime (`httpSend`) | `/realtime/v1/` | `realtime` |

If your project URL has a path, such as `https://example.com/supabase`, the request path starts
with it. Add it to the prefix.

### Add a middleware for one sub-client

Wrap your middleware in one that checks the path. Other requests go straight to `next`.

```swift
struct OnlyForPath: ClientMiddleware {
  let prefix: String
  let inner: any ClientMiddleware

  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    next: nonisolated(nonsending) @Sendable (HTTPRequest, HTTPBody?) async throws -> (
      HTTPResponse, HTTPBody?
    )
  ) async throws -> (HTTPResponse, HTTPBody?) {
    guard request.path?.hasPrefix(prefix) == true else {
      return try await next(request, body)
    }
    return try await inner.intercept(request, body: body, next: next)
  }
}

var configuration = SupabaseClient.Configuration()
configuration.global.http.middlewares = [
  OnlyForPath(prefix: "/storage/v1/", inner: uploadMetrics)
]
```

### Use another transport for one sub-client

A transport can pick a delegate by path, for example a `URLSession` that keeps Storage off
cellular data. Do not use a background `URLSession` here: Storage also sends requests that need
a data task, and a background session does not support data tasks.

```swift
struct RoutingTransport: ClientTransport {
  let storage: URLSessionTransport
  let other: URLSessionTransport

  func send(_ request: HTTPRequest, body: HTTPBody?) async throws -> (HTTPResponse, HTTPBody?) {
    if request.path?.hasPrefix("/storage/v1/") == true {
      return try await storage.send(request, body: body)
    }
    return try await other.send(request, body: body)
  }
}

let storageSession = URLSessionConfiguration.default
storageSession.allowsCellularAccess = false

configuration.global.http.transport = RoutingTransport(
  storage: URLSessionTransport(session: URLSession(configuration: storageSession)),
  other: URLSessionTransport()
)
```

### Change the timeout of one call

The timeout in ``SupabaseClient/Configuration/Global/http`` applies to every request. Edge
Functions use 150 seconds when you leave it `nil`. For one longer call, use
`PostgrestRequestBuilder.timeout(_:)` or `FunctionInvokeOptions.timeout`.

### Receive the SDK's logs

The SDK is silent by default: without a logger, it emits nothing in any build configuration.
Pass a swift-log `Logger` to receive its lines. Each HTTP request logs one `.debug` line with
the method, the URL without its query, the status code or a failure summary, and the duration.
No line holds a credential, a token, a header value, a query string, or
a request or response body.

```swift
import Logging

var logger = Logger(label: "io.supabase")
logger.logLevel = .debug
configuration.global.logger = logger
```

### Filter the logs of one sub-client

Each sub-client sets the `system` metadata key on its log messages. A `LogHandler` can keep the
messages of one sub-client and drop the rest.

```swift
struct SystemFilter: LogHandler {
  let system: String
  var base: any LogHandler

  var logLevel: Logger.Level {
    get { base.logLevel }
    set { base.logLevel = newValue }
  }

  var metadata: Logger.Metadata {
    get { base.metadata }
    set { base.metadata = newValue }
  }

  subscript(metadataKey key: String) -> Logger.Metadata.Value? {
    get { base[metadataKey: key] }
    set { base[metadataKey: key] = newValue }
  }

  func log(event: LogEvent) {
    guard (event.metadata?["system"] ?? base.metadata["system"]) == .string(system) else { return }
    base.log(event: event)
  }
}

configuration.global.logger = Logger(label: "io.supabase") { label in
  SystemFilter(system: "auth", base: StreamLogHandler.standardOutput(label: label))
}
configuration.global.logger.logLevel = .debug
```
