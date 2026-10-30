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

The client does not check for this. Each attempt to open the socket fails with a
``RealtimeError/Kind-swift.struct/transport`` error, and ``RealtimeChannel/subscribe()`` keeps
retrying the join.

For a watch app, get live data through the paired iPhone app, for example with
WatchConnectivity, or poll over HTTP.

### Linux and Android

On Linux and Android the default transport runs on swift-corelibs-foundation, whose
`URLSessionWebSocketTask` uses libcurl. libcurl must be built with WebSocket support. The SDK
builds on Linux, but Linux and Android are not supported for production use.

If the default transport does not work on your platform, implement ``WebSocketTransport`` over
another WebSocket stack, such as one built on SwiftNIO. See <doc:CustomTransports>.

``RealtimeClientOptions/handleAppLifecycle`` works only on iOS, macOS, tvOS and visionOS. On
watchOS, Linux and Android its default is `false`, and setting it to `true` does nothing.

### Message size

``URLSessionWebSocketTransport`` accepts frames up to 5,000,000 bytes. That is the largest frame
the server sends, so a large row or broadcast always fits. `URLSessionWebSocketTask` on its own
stops at 1 MiB and drops the socket on a larger frame. The limit is fixed; there is no option to
change it.

A custom transport sets its own limit. Make it at least 5,000,000 bytes.
