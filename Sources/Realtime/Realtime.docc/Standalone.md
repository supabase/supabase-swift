# Standalone Use

Build a ``RealtimeClient`` without `SupabaseClient`: your own token source and transport.

## Overview

``RealtimeClient/init(configuration:)`` takes a ``RealtimeClient/Configuration``. Only
``RealtimeClient/Configuration/url`` is required. Pass the headers the server needs, usually
`apikey`.

```swift
let realtime = try RealtimeClient(
  configuration: RealtimeClient.Configuration(
    url: URL(string: "https://<ref>.supabase.co/realtime/v1")!,
    headers: [.apikey: "sb_publishable_…"],
    accessToken: { try await tokenStore.current() }
  )
)

let channel = await realtime.channel("room:42")
```

The initializer throws a ``RealtimeError`` of kind
``RealtimeError/Kind-swift.struct/invalidConfiguration`` when the URL has no scheme or no host.

### Authorization

``RealtimeClient/Configuration/accessToken`` supplies the token for every join. The client calls
it before a join, when a heartbeat goes out, and shortly before the token expires. A call that
throws or returns `nil` keeps the current token. To set a token yourself, call
``RealtimeClient/setAuth(_:)``.

Do not add an `AccessTokenMiddleware` to ``RealtimeClient/Configuration/http``. See <doc:Auth>.

### The WebSocket transport

``RealtimeClient/Configuration/webSocketTransport`` is the stack that the client connects with.
The default is ``URLSessionWebSocketTransport``. Pass a configured one to pin certificates, or
your own ``WebSocketTransport`` to use another stack. See <doc:CustomTransports>.

### The HTTP transport

``RealtimeClient/Configuration/http`` is the `HTTPClientConfiguration` every module shares. Only
``RealtimeChannel/httpSend(event:payload:encoder:timeout:)`` uses it. The WebSocket does not.

### Timing

- ``RealtimeClient/Configuration/heartbeatInterval`` is the time between heartbeats.
- ``RealtimeClient/Configuration/requestTimeout`` is the limit for a subscribe, a push and a REST
  broadcast.
- ``RealtimeClient/Configuration/connectsOnSubscribe`` lets
  ``RealtimeChannel/subscribe()`` open the socket. When it is `false`, call
  ``RealtimeClient/connect()`` yourself.
- ``RealtimeClient/Configuration/disconnectOnEmptyChannelsAfter`` is how long the socket stays
  open after the last channel is removed.

See <doc:ConnectionBehavior> for reconnects, the app lifecycle and network changes.

### Logger and clock

``RealtimeClient/Configuration/logger`` is a swift-log `Logger`. The client removes tokens,
secrets and URL query strings from each line, and tags the logger with `system=realtime`.

``RealtimeClient/Configuration/clock`` is the clock for the heartbeat timer and the reconnect
backoff. Pass a test clock to control them in tests.
