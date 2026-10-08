# Platform Notes

What differs on watchOS, Linux and Android, and how large a frame the client accepts.

## Overview

The default transport, ``URLSessionWebSocketTransport``, uses `URLSessionWebSocketTask`. It
behaves the same on iOS, iPadOS, macOS, Mac Catalyst, tvOS and visionOS. The other platforms
have limits.

### watchOS

watchOS allows low-level networking, WebSockets included, only in a few cases, such as an app
that streams audio. See Apple's TN3135, "Low-level networking on watchOS". Outside
those cases the system refuses the connection.

The client does not check for this today. Each connect fails with a transport error, and the
client keeps retrying on ``RealtimeClientOptions/reconnect``, so the status cycles between
``RealtimeConnectionStatus/connecting(attempt:)`` and
``RealtimeConnectionStatus/reconnecting(attempt:retryIn:lastError:)``.

For a watch app, get live data through the paired iPhone app, for example with
WatchConnectivity, or poll over HTTP.

### Linux and Android

On Linux and Android the default transport runs on swift-corelibs-foundation, whose
`URLSessionWebSocketTask` uses libcurl. libcurl must be built with WebSocket support. The SDK
builds on Linux, but production use there is not supported. Android is not tested.

If the default transport does not work on your platform, implement ``WebSocketTransport`` over
another WebSocket stack, such as one built on SwiftNIO. See <doc:CustomTransports>.

``RealtimeClientOptions/handleAppLifecycle`` works only on iOS, tvOS, visionOS and macOS. On
watchOS, Linux and Android it does nothing.

### Message size

``RealtimeClientOptions/maximumMessageSize`` is the largest frame the default transport
receives, 5,000,000 bytes by default. That is the largest frame the server sends, so a large
row or broadcast always fits. `URLSessionWebSocketTask` on its own stops at 1 MiB and drops the
socket on a larger frame.

The option applies only to ``URLSessionWebSocketTransport``. A custom transport sets its own
limit; make it at least 5,000,000 bytes.
