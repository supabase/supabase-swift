# Standalone Use

Build a ``FunctionsClient`` without `SupabaseClient`: your own token source, transport and
middleware.

## Overview

``FunctionsClient/init(configuration:)`` takes a ``FunctionsClient/Configuration``. Only
``FunctionsClient/Configuration/url`` is required.

```swift
let functions = FunctionsClient(
  configuration: .init(
    url: URL(string: "https://<ref>.supabase.co/functions/v1")!,
    headers: [HTTPField.Name("apikey")!: "sb_publishable_…"],
    region: .usEast1,
    accessToken: { await tokenStore.current }
  )
)
```

The initializer traps when the URL has no host. The URL is fixed at construction, so a bad one
is a programmer error and is reported where it was introduced.

### Authorization

``FunctionsClient/Configuration/accessToken`` is called for every request. A non-`nil` result is
sent as `Authorization: Bearer <token>` unless the request already carries `Authorization`; a
per-call ``FunctionInvokeOptions/headers`` entry therefore wins. Whatever the closure throws
propagates as itself.

``FunctionsClient/Configuration/headers`` must not carry `Authorization`. A static bearer would
win over every token the closure returns, so debug builds report an issue when it does. Send
`apikey` there; send the user's JWT through the closure.

A new-format `sb_publishable_` or `sb_secret_` key is an `apikey`, never a bearer. With
`verify_jwt` on, the gateway accepts a request that carries only `apikey`.

### Transport and middleware

``FunctionsClient/Configuration/http`` is the `HTTPClientConfiguration` every module shares: a
`ClientTransport` performs the exchange and an ordered `ClientMiddleware` chain runs in front of
it. Your middlewares run first, then the SDK adds the bearer and logs the request on the wire.
A middleware of yours therefore never sees the token.

```swift
let functions = FunctionsClient(
  configuration: .init(
    url: url,
    http: .init(
      transport: URLSessionTransport(session: session),
      middlewares: [RetryBudget(), MetricsMiddleware()],
      timeout: .seconds(60)
    )
  )
)
```

`timeout` is the idle timeout for every call. When `nil`, ``FunctionsClient/requestIdleTimeout``
applies. A per-call ``FunctionInvokeOptions/timeout`` overrides both.

### Logger and decoder

``FunctionsClient/Configuration/logger`` is a swift-log `Logger`; the client tags it with
`system=functions`. ``FunctionsClient/Configuration/decoder`` is the decoder every JSON-decoding
call uses unless it passes its own.
