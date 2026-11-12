# Standalone Use

Build a ``FunctionsClient`` without `SupabaseClient`: your own token source, transport and
middleware.

## Overview

``FunctionsClient/init(configuration:)`` takes a ``FunctionsClient/Configuration``. Only
``FunctionsClient/Configuration/url`` is required.

```swift
let functions = try FunctionsClient(
  configuration: .init(
    url: URL(string: "https://<ref>.supabase.co/functions/v1")!,
    headers: [.apikey: "sb_publishable_…"],
    region: .usEast1,
    http: .init(middlewares: [AccessTokenMiddleware { await tokenStore.current }])
  )
)
```

The initializer throws a ``FunctionsError`` of kind
``FunctionsError/Kind-swift.struct/invalidConfiguration`` when the URL has no scheme or no host.

### Authorization

An `AccessTokenMiddleware` in ``FunctionsClient/Configuration/http`` is the one way to send a
user's token. It calls its closure for every request. A non-`nil` result is sent as
`Authorization: Bearer <token>` unless the request already carries `Authorization`; a static
``FunctionsClient/Configuration/headers`` entry or a per-call ``FunctionInvokeOptions/headers``
entry therefore wins. If the closure throws, the call throws ``FunctionsError`` with kind
``FunctionsError/Kind-swift.struct/accessToken``, and the closure's error in
``FunctionsError/underlyingError``.

A new-format `sb_publishable_` or `sb_secret_` key is an `apikey`, never a bearer. With
`verify_jwt` on, the gateway accepts a request that carries only `apikey`.

### Transport and middleware

``FunctionsClient/Configuration/http`` is the `HTTPClientConfiguration` every module shares: a
`ClientTransport` performs the exchange and an ordered `ClientMiddleware` chain runs in front of
it. Your middlewares run in order, then the SDK logs the request on the wire. A middleware after
the `AccessTokenMiddleware` sees the token; one before it does not.

```swift
let functions = try FunctionsClient(
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
