# Standalone Use

Build a ``StorageClient`` without `SupabaseClient`: your own token source, transport and
middleware.

## Overview

``StorageClient/init(configuration:)`` takes a ``StorageClientConfiguration``. It needs the
Storage URL and the headers every request carries, usually `apikey`.

```swift
let storage = StorageClient(
  configuration: StorageClientConfiguration(
    url: URL(string: "https://<ref>.supabase.co/storage/v1")!,
    headers: [HTTPField.Name("apikey")!: "sb_publishable_…"],
    http: HTTPClientConfiguration(
      middlewares: [AccessTokenMiddleware { try await tokenStore.current() }]
    )
  )
)
let avatars = storage.from("avatars")
```

The initializer traps when the URL has no host. The URL is fixed at construction, so a bad one
is a programmer error and is reported where it was introduced.

### Authorization

A user's token enters a request through the middleware chain, never through a configuration
field. `AccessTokenMiddleware` calls its closure for every request and sends a non-`nil` result
as `Authorization: Bearer <token>`. A token that rotates is therefore always current. Whatever
the closure throws fails that request and reaches you unchanged.

The middleware sets the header only when the request has none. A static `Authorization` in
``StorageClientConfiguration/headers`` is sent as it is and wins over the middleware, so leave it
out and send the user's JWT through the closure.

A new-format `sb_publishable_` or `sb_secret_` key is an `apikey`, never a bearer. Some calls,
such as ``StorageBucket/purgeCache(path:includingTransformations:)``, need the `secret` key.

### Extra headers

``StorageClient/setHeader(name:value:)`` and ``StorageBucket/setHeader(name:value:)`` return a
copy that sends one more header. They do not change the original. Discard the result and the
call does nothing.

```swift
let traced = storage.setHeader(name: HTTPField.Name("x-trace")!, value: traceID)
try await traced.from("avatars").upload(path: "a.png", data: data)
```

### Transport and middleware

``StorageClientConfiguration/http`` is the `HTTPClientConfiguration` every module shares. A
`ClientTransport` performs the exchange. The default is `URLSessionTransport` over
`URLSession.shared`. An ordered `ClientMiddleware` chain runs in front of it.

```swift
let storage = StorageClient(
  configuration: StorageClientConfiguration(
    url: storageURL,
    headers: headers,
    http: HTTPClientConfiguration(
      transport: URLSessionTransport(session: session),
      middlewares: [AccessTokenMiddleware { try await tokenStore.current() }, MetricsMiddleware()],
      timeout: .seconds(120)
    )
  )
)
```

Your middlewares run in array order, then the SDK logs the request on the wire. Each retry runs
the whole chain again, so a replayed request gets a fresh token.

`timeout` is an idle timeout: a request fails once no data has moved for this long, so a slow
but steady upload is not cut short. The default is 60 seconds.

### Retries

``StorageClientConfiguration/retryEnabled`` is `true` by default. The SDK then retries reads that
fail with a transient error or status: `GET` and `HEAD` requests and the listing calls, up to
three attempts with jittered backoff. A `Retry-After` header is honored. Uploads, moves, copies,
removals and bucket changes are never replayed. See <doc:HandlingErrors>.

### Hostname and logger

``StorageClientConfiguration/usesNewHostname`` rewrites `<ref>.supabase.co` to
`<ref>.storage.supabase.co`. The direct storage host does not buffer requests, which allows
uploads over 50 GB. Resumable uploads use that host whatever this flag says. See
<doc:ResumableUploads>.

``StorageClientConfiguration/logger`` is a swift-log `Logger`; the client tags it with
`system=storage`.
