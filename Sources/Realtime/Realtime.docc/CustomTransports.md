# Custom Transports

Replace the WebSocket stack, pin certificates, or drive the client from a test.

## Overview

The client reaches the network only through ``WebSocketTransport``. Set
``RealtimeClientOptions/webSocketTransport`` to use your own; leave it `nil` for
``URLSessionWebSocketTransport``.

### Pinning certificates

You rarely need a new transport for TLS. ``URLSessionWebSocketTransport/init(configuration:delegate:)``
takes a `URLSessionDelegate` and sends it the TLS and authentication challenges of every
connection:

```swift
nonisolated final class PinningDelegate: NSObject, URLSessionDelegate {
  func urlSession(
    _ session: URLSession,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    guard let trust = challenge.protectionSpace.serverTrust, isPinned(trust) else {
      completionHandler(.cancelAuthenticationChallenge, nil)
      return
    }
    completionHandler(.useCredential, URLCredential(trust: trust))
  }
}

var options = RealtimeClientOptions()
options.webSocketTransport = URLSessionWebSocketTransport(delegate: PinningDelegate())
```

`isPinned(_:)` is your check, for example a comparison of the leaf certificate's public key with
the one you ship. URLSession calls the delegate off the main actor, so in an app with default
main actor isolation the delegate and `isPinned(_:)` must be `nonisolated`.

The transport copies `configuration` into a new `URLSession` for each connection, so proxy and
timeout settings apply too.

### Writing a transport

A transport opens one connection per call to
``WebSocketTransport/connect(to:headerFields:)``. The client holds one connection at a time.
Follow the contract in each requirement's documentation. In short:

- Throw a ``RealtimeError`` when the upgrade fails. Set ``RealtimeError/isRetryable`` to `false`
  for an answer that cannot change, such as a 401, and the client stops retrying. Rethrow
  `CancellationError` when the task is cancelled during the handshake.
- ``WebSocketConnection/events`` yields every frame, then exactly one
  ``WebSocketEvent/closed(code:reason:)``, then finishes. A close is an event, never a thrown
  error.
- ``WebSocketConnection/send(_:)`` sends frames in call order.
- Accept frames up to 5,000,000 bytes. See <doc:PlatformNotes>.

``WebSocketTransport`` and ``WebSocketConnection`` refine `Sendable`, so their conformances
cannot be isolated to the main actor. In an app with default main actor isolation, mark your
types `nonisolated`:

```swift
nonisolated struct NIOTransport: WebSocketTransport {
  func connect(to url: URL, headerFields: HTTPFields) async throws -> any WebSocketConnection {
    // Open the socket with your stack and wrap it.
  }
}
```

### Testing with a stub

A stub transport lets a test play the server: read what the client sends, and push frames
back.

```swift
actor StubConnection: WebSocketConnection {
  nonisolated let events: AsyncStream<WebSocketEvent>
  private let continuation: AsyncStream<WebSocketEvent>.Continuation
  private(set) var sent: [WebSocketFrame] = []

  init() {
    (events, continuation) = AsyncStream.makeStream(of: WebSocketEvent.self)
  }

  func send(_ frame: WebSocketFrame) async throws {
    sent.append(frame)
  }

  func close(code: WebSocketCloseCode, reason: String?) async {
    continuation.yield(.closed(code: code, reason: reason))
    continuation.finish()
  }

  nonisolated func receive(_ text: String) {
    continuation.yield(.frame(.text(text)))
  }
}

struct StubTransport: WebSocketTransport {
  let connection: StubConnection

  func connect(to url: URL, headerFields: HTTPFields) async throws -> any WebSocketConnection {
    connection
  }
}
```

The client speaks the Phoenix protocol, version 2.0.0: each text frame is a JSON array
`[join_ref, ref, topic, event, payload]`. To let ``RealtimeChannel/subscribe()`` return, read
the `phx_join` frame from `sent` and reply with its `join_ref` and `ref`:

```swift
connection.receive(#"["1","1","realtime:room","phx_reply",{"status":"ok","response":{}}]"#)
```

Set ``RealtimeClientOptions/handleAppLifecycle`` to `false` in tests. To control heartbeats,
timeouts and retries, pass your own ``RealtimeClientOptions/clock``.
