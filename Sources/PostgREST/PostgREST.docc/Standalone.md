# Standalone Use

Build a ``PostgrestClient`` without `SupabaseClient`: your own token source, transport and
middleware.

## Overview

``PostgrestClient/init(configuration:)`` takes a ``PostgrestClient/Configuration``. Only
``PostgrestClient/Configuration/url`` is required. Pass the headers every request carries,
usually `apikey`.

```swift
let database = try PostgrestClient(
  configuration: PostgrestClient.Configuration(
    url: URL(string: "https://<ref>.supabase.co/rest/v1")!,
    headers: [.apikey: "sb_publishable_…"],
    http: HTTPClientConfiguration(
      middlewares: [AccessTokenMiddleware { try await tokenStore.current() }]
    )
  )
)
```

The initializer throws a ``PostgrestError`` of kind
``PostgrestError/Kind-swift.struct/invalidConfiguration`` when the URL has no scheme or no host.

### Authorization

An `AccessTokenMiddleware` in ``PostgrestClient/Configuration/http`` sends a user's token. It
runs on every attempt, so a retried request gets a fresh token. An `Authorization` header in
``PostgrestClient/Configuration/headers`` or on the request wins over the middleware. If the
closure throws, the call throws a ``PostgrestError`` with kind
``PostgrestError/Kind-swift.struct/accessToken``.

### Schema

``PostgrestClient/Configuration/schema`` is the Postgres schema to query. `nil` uses the server
default, which is `public`. ``PostgrestClient/schema(_:)`` returns a client for another schema.

### Transport and middleware

``PostgrestClient/Configuration/http`` is the `HTTPClientConfiguration` every module shares. A
`ClientTransport` performs the exchange. The default is `URLSessionTransport` over
`URLSession.shared`. An ordered `ClientMiddleware` chain runs in front of it.

```swift
let database = try PostgrestClient(
  configuration: PostgrestClient.Configuration(
    url: databaseURL,
    headers: headers,
    http: HTTPClientConfiguration(
      transport: URLSessionTransport(session: session),
      middlewares: [MetricsMiddleware()],
      timeout: .seconds(30)
    )
  )
)
```

Your middlewares run in array order. Each retry runs the whole chain again.

### Coders

``PostgrestClient/Configuration/encoder`` and ``PostgrestClient/Configuration/decoder`` are the
JSON coders for request bodies and response bodies. The defaults read and write `Date` the way
Postgres does. To change one setting, start from `JSONEncoder.supabase()` or
`JSONDecoder.supabase()`, so dates still work.

```swift
let decoder = JSONDecoder.supabase()
decoder.keyDecodingStrategy = .convertFromSnakeCase

var configuration = PostgrestClient.Configuration(url: databaseURL, headers: headers)
configuration.decoder = decoder
```

### Retries and logger

``PostgrestClient/Configuration/retryEnabled`` is `true` by default. See <doc:HandlingErrors>.

``PostgrestClient/Configuration/logger`` is a swift-log `Logger`. The client removes tokens,
secrets and URL query strings from each line, and tags the logger with `system=postgrest`.
