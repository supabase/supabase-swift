# Standalone Use

Build an ``AuthClient`` without `SupabaseClient`: your own storage, transport and middleware.

## Overview

``AuthClient/init(configuration:)`` takes an ``AuthClient/Configuration``. It needs the Auth URL
and the key to store the session under. Pass the headers every request carries, usually
`apikey`.

```swift
let auth = try AuthClient(
  configuration: AuthClient.Configuration(
    url: URL(string: "https://<ref>.supabase.co/auth/v1")!,
    storageKey: "sb-<ref>-auth-token",
    headers: [.apikey: "sb_publishable_…"],
    redirectTo: URL(string: "myapp://auth-callback")
  )
)
```

The initializer throws an ``AuthError`` of kind
``AuthError/Kind-swift.struct/invalidConfiguration`` when the URL has no scheme or no host.

### Storage

``AuthClient/Configuration/storage`` is where the client keeps the session and its pending
sign-in flows. The default is ``KeychainStorage`` on Apple platforms and ``InMemoryAuthStorage``
on Linux, Android and Windows. With in-memory storage, the user signs in again after the process
restarts. To keep the session there, pass your own ``AuthStorage``.

Two clients that share one storage need different values of
``AuthClient/Configuration/storageKey``. `SupabaseClient` uses `sb-<project-ref>-auth-token`.
Use the same key if your client must read a session that a `SupabaseClient` stored.

### Token refresh

``AuthClient/Configuration/autoRefresh`` is an ``AuthClient/AutoRefreshPolicy``:

- ``AuthClient/AutoRefreshPolicy/automatic``, the default, refreshes the session before its
  access token expires.
- ``AuthClient/AutoRefreshPolicy/manual`` refreshes an expired session only when
  ``AuthClient/session()`` needs it.
- ``AuthClient/AutoRefreshPolicy/disabled`` never refreshes. Use it in an app extension that
  shares storage with the main app. See <doc:SharingASessionWithAnAppExtension>.

``AuthClient/Configuration/observesAppLifecycle`` pauses auto refresh while the app is in the
background. Set it to `false` to call ``AuthClient/startAutoRefresh()`` and
``AuthClient/stopAutoRefresh()`` yourself.

### Authorize your own requests

A standalone client does not add the session to requests that you send to other services. Read
the token from ``AuthClient/session()``. It refreshes an expired session before it returns.

```swift
let http = HTTPClientConfiguration(
  middlewares: [AccessTokenMiddleware { try await auth.session().accessToken }]
)
```

Pass this `HTTPClientConfiguration` to a standalone client of another module. Do not pass it to
the ``AuthClient`` itself.

### Transport and middleware

``AuthClient/Configuration/http`` is the `HTTPClientConfiguration` every module shares. A
`ClientTransport` performs the exchange. The default is `URLSessionTransport` over
`URLSession.shared`. An ordered `ClientMiddleware` chain runs in front of it.

```swift
let auth = try AuthClient(
  configuration: AuthClient.Configuration(
    url: authURL,
    storageKey: "sb-<ref>-auth-token",
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

### Retries, logger and clock

``AuthClient/Configuration/retryEnabled`` is `true` by default. The SDK then retries `GET`
requests that fail with a transient error. See <doc:HandlingErrors>.

``AuthClient/Configuration/logger`` is a swift-log `Logger`. The client removes tokens, secrets
and URL query strings from each line, and tags the logger with `system=auth`.

``AuthClient/Configuration/clock`` and ``AuthClient/Configuration/now`` let a test control token
refresh and expiry. Keep the two in step.

### Admin calls

``AuthAdminClient`` is a separate client for the admin API. It needs a secret key, so use it only
on a server. Never ship a secret key in an app.
