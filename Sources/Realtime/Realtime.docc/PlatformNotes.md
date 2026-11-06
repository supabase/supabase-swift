# Platform Notes

What differs on watchOS, Linux and Android, and how large a frame the client accepts.

## Overview

The default transport, ``URLSessionWebSocketTransport``, uses `URLSessionWebSocketTask`. It
behaves the same on iOS, iPadOS, macOS, Mac Catalyst, tvOS and visionOS. The other platforms
have limits.

### watchOS

watchOS allows low-level networking, WebSockets included, only in a few cases, such as an app
that streams audio. See Apple's
[TN3135: Low-level networking on watchOS](https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos).
Outside those cases the system refuses the connection.

``URLSessionWebSocketTransport`` fails fast on watchOS. ``RealtimeClient/connect()`` throws a
``RealtimeError/Kind-swift.struct/transport`` error that cites TN3135 and has
``RealtimeError/isRetryable`` set to `false`, so ``RealtimeChannel/subscribe()`` fails with the
same error instead of retrying the join. Without the check the connection would wait forever.

If your app runs in a context that TN3135 allows, such as audio streaming, opt in:

```swift
var configuration = RealtimeClient.Configuration(url: realtimeURL)
configuration.webSocketTransport = URLSessionWebSocketTransport(allowsWatchOSConnections: true)
```

With the opt-in, the transport also gives up on a handshake that does not finish within the
`timeoutIntervalForRequest` of its configuration (60 seconds by default). It throws a retryable
``RealtimeError/Kind-swift.struct/transport`` error that cites TN3135, because on watchOS the
system may not time out the connection itself.

For a watch app, get live data through the paired iPhone app, for example with
WatchConnectivity, or poll over HTTP.

### Linux and Android

On Linux and Android the default transport runs on swift-corelibs-foundation, whose
`URLSessionWebSocketTask` uses libcurl. libcurl must be built with WebSocket support. The SDK
builds on Linux, but Linux and Android are not supported for production use.

If the default transport does not work on your platform, implement ``WebSocketTransport`` over
another WebSocket stack, such as one built on SwiftNIO. See <doc:CustomTransports>.

``RealtimeClient/Configuration/handleAppLifecycle`` works only on iOS, macOS, tvOS and visionOS. On
watchOS, Linux and Android its default is `false`, and setting it to `true` does nothing.

``RealtimeClient/Configuration/monitorsNetworkPath`` is on by default on iOS, macOS, tvOS and visionOS.
On watchOS it is off, because the system keeps reporting an unsatisfied path to ordinary apps,
so the hint may never fire. Linux and Android have no path monitor, so the option does nothing
there.

### Message size

``URLSessionWebSocketTransport`` accepts frames up to 5,000,000 bytes. That is the largest frame
the server sends, so a large row or broadcast always fits. `URLSessionWebSocketTask` on its own
stops at 1 MiB and drops the socket on a larger frame. The limit is fixed; there is no option to
change it.

A custom transport sets its own limit. Make it at least 5,000,000 bytes.
