# Connection Behavior

How the client reports, keeps and recovers its socket, and how it behaves when the app goes to
the background.

## Overview

The client opens the socket on the first ``RealtimeChannel/subscribe()``, or on
``RealtimeClient/connect()``. After that it keeps the socket open by itself: it sends
heartbeats, reconnects after a drop, and joins every channel again. You watch this through two
statuses.

### Statuses

``RealtimeClient/status`` is a ``RealtimeConnectionStatus``. ``RealtimeChannel/status`` is a
``RealtimeChannelStatus``. Each one is also a stream, ``RealtimeClient/statusChanges`` and
``RealtimeChannel/statusChanges``, that starts with the current value and keeps only the newest
one, so a slow consumer skips to the latest status.

The status types are not `Equatable`. Use the predicates, or pattern match for the details:

```swift
for await status in supabase.realtime.statusChanges {
  banner.isVisible = !status.isConnected
  if case .reconnecting(let attempt, let retryIn, _) = status {
    banner.text = "Reconnecting in \(retryIn) (attempt \(attempt))"
  }
}
```

``RealtimeConnectionStatus/error`` and ``RealtimeChannelStatus/error`` carry the last failure.
A recoverable failure stays in the status; it never ends a data stream.

### Reconnect and rejoin

``RealtimeClientOptions/reconnect`` is the ``BackoffPolicy`` for the socket. The default,
``BackoffPolicy/fullJitter(base:cap:)`` with a 1-second base and a 30-second cap, spreads
clients out after an outage. ``RealtimeClientOptions/rejoin`` is the policy for a channel the
server dropped while the socket stayed up. Its default is ``BackoffPolicy/steps(_:)`` with 1, 2,
5 and 10 seconds.

The client stops retrying when the answer cannot change:

- A WebSocket upgrade refused with 401, 403 or 404 ends in
  ``RealtimeConnectionStatus/disconnected(_:)`` with the error, and ``RealtimeClient/connect()``
  throws.
- A join the server refuses for good, such as a denied policy, ends in
  ``RealtimeChannelStatus/failed(_:)``. Fix the cause, then subscribe again.

A rate limit from the server makes the channel wait longer than its normal steps before it
joins again.

### Heartbeat and liveness

The client sends a heartbeat every ``RealtimeClientOptions/heartbeatInterval`` (25 seconds by
default). When no reply comes within ``RealtimeClientOptions/heartbeatTimeout`` (10 seconds),
it closes the socket and reconnects. ``RealtimeClient/heartbeats`` reports each step, with the
round-trip latency of each reply.

The heartbeat runs on ``RealtimeClientOptions/clock``, a `ContinuousClock` by default. That
clock keeps counting while the device sleeps, so after a long sleep the next heartbeat is due at
once, and a dead socket shows within one heartbeat timeout.

### Background and foreground on iOS

The client never disconnects when the app goes to the background. iOS suspends the app soon
after, and may close the socket while it is suspended. Disconnecting first gains nothing:

- A short trip to the background, such as a share sheet or a phone call, would cost a full
  reconnect, a rejoin of every channel, and a presence leave and join seen by everyone else.
- A suspended app cannot finish a graceful leave without a background task.

When the app comes back, the client recovers. With ``RealtimeClientOptions/handleAppLifecycle``
on (the default), a socket that waits out a reconnect delay tries again at once. A socket that
iOS closed is found by the transport or by the next heartbeat. Either way the client
reconnects, the channels join again, and each yields ``RealtimeChannelEvent/resubscribed``.

### Pausing with the scene phase

To close the socket in the background, call ``RealtimeClient/pause()`` and
``RealtimeClient/resume()`` from the scene phase:

```swift
@main
struct ChatApp: App {
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup { ContentView() }
      .onChange(of: scenePhase) { _, phase in
        Task {
          switch phase {
          case .background: await supabase.realtime.pause()
          case .active: await supabase.realtime.resume()
          default: break
          }
        }
      }
  }
}
```

``RealtimeClient/pause()`` closes the socket but keeps every channel that wants its
subscription. ``RealtimeClient/resume()`` reconnects and joins them again. Streams stay open
across the pause, so your loops keep running. ``RealtimeClient/disconnect()`` is different: it
leaves every channel, and you subscribe them again yourself.

### Idle socket

With ``RealtimeClientOptions/connectOnSubscribe`` on, a subscribe opens the socket when it is
closed. When the last channel is removed, the socket stays open for
``RealtimeClientOptions/disconnectOnEmptyChannelsAfter`` (50 seconds by default) in case a new
channel comes, then closes.
