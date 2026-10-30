# Connection Behavior

How the client reports, keeps and recovers its socket, and how it behaves when the app goes to
the background.

## Overview

The client opens the socket on the first ``RealtimeChannel/subscribe()``, or on
``RealtimeClient/connect()``. After that it keeps the socket open by itself: it sends
heartbeats, reconnects after a drop, and joins every channel again. You watch this through two
statuses.

### Statuses

``RealtimeClient/status`` is a ``RealtimeClientStatus``. ``RealtimeChannel/status`` is a
``RealtimeChannelStatus``. Each one is also a stream, ``RealtimeClient/statusChanges()`` and
``RealtimeChannel/statusChanges()``, that starts with the current value and then yields every
change.

The status types are not `Equatable`. Use the predicates, or match a case for the details:

```swift
for await status in await supabase.realtime.statusChanges() {
  isBannerVisible = !status.isConnected
  if case .reconnecting(let attempt, let retryIn, _) = status {
    bannerText = "Reconnecting in \(retryIn) (attempt \(attempt + 1))"
  }
}
```

``RealtimeClientStatus/error`` and ``RealtimeChannelStatus/error`` carry the last failure. A
failure the client can recover from stays in the status; it never ends a data stream.

### Reconnect and rejoin

When the socket drops, the client waits a random time and connects again. The wait for attempt
`n` is up to `min(30 s, 1 s × 2^(n-1))`, so many clients spread out after an outage. During the
wait the status is ``RealtimeClientStatus/reconnecting(attempt:retryIn:lastError:)``. Calling
``RealtimeClient/connect()`` in that time tries again at once.

A channel whose join fails waits in
``RealtimeChannelStatus/resubscribing(attempt:retryIn:lastError:)`` and joins again after 1, 2
and 5 seconds, then every 10 seconds. After a rate limit from the server it waits 30 seconds.
There is no attempt limit; cancel the task that called ``RealtimeChannel/subscribe()`` to stop
waiting.

The client stops when the answer cannot change:

- A WebSocket upgrade refused with 401, 403 or 404 ends in
  ``RealtimeClientStatus/disconnected(_:)`` with the error.
- A join the server refuses for good, such as one a policy denies, ends in
  ``RealtimeChannelStatus/failed(_:)``. Fix the cause, then subscribe again.

A failure in ``RealtimeClient/connect()`` itself is not retried: `connect()` throws it.

### When the server closes a channel

The automatic rejoin covers a dropped socket. It does not cover a channel that the server ends
while the socket stays up, for example when the token expires:

- After a close (`phx_close`), the channel's status becomes
  ``RealtimeChannelStatus/unsubscribed``, the client removes the channel, and every stream on it
  ends. Your `for await` loops end. To keep receiving events, ask the client for a new channel
  and subscribe it.
- After a channel error (`phx_error`), the status becomes
  ``RealtimeChannelStatus/unsubscribed``, but the channel and its streams stay. Call
  ``RealtimeChannel/subscribe()`` again.

In both cases ``RealtimeChannel/statusChanges()`` reports ``RealtimeChannelStatus/unsubscribed``
without a call from you. Watch for it if your screen must stay live.

### Heartbeat and liveness

The client sends a heartbeat every ``RealtimeClientOptions/heartbeatInterval`` (25 seconds by
default). When the next heartbeat is due and the server has not answered the last one, the
client closes the socket and reconnects. So a dead socket is found within two intervals.
``RealtimeClient/heartbeats()`` reports each step, with the round-trip latency of each answer.

The heartbeat runs on ``RealtimeClientOptions/clock``, a `ContinuousClock` by default. That
clock keeps counting while the device sleeps, so after a long sleep the next heartbeat is due at
once.

### Background and foreground on iOS

The client never disconnects when the app goes to the background. iOS suspends the app soon
after, and may close the socket while it is suspended. Disconnecting first gains nothing:

- A short trip to the background, such as a share sheet or a phone call, would cost a full
  reconnect, a join of every channel, and a presence leave and join that everyone else sees.
- A suspended app cannot finish a clean leave without a background task.

When the app comes back, the client recovers. With ``RealtimeClientOptions/handleAppLifecycle``
on (the default on iOS, macOS, tvOS and visionOS), the client checks the socket on foreground:

- If it is waiting before a reconnect attempt, it tries again at once.
- If the socket was connected before the app went to the background and is now closed, it
  connects and joins every channel again.

A socket that looks open but is dead is found by the next heartbeat. In each case the channels
join again and yield ``RealtimeChannelEvent/resubscribed``.

### Closing the socket in the background

To close the socket when the app goes to the background, tie the channels to the scene phase.
When the task ends, it removes its channel; when the app comes back, the task starts again:

```swift
struct RoomView: View {
  let roomID: UUID
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    MessageList(roomID: roomID)
      .task(id: scenePhase == .background) {
        guard scenePhase != .background else { return }
        let channel = await supabase.channel("room:\(roomID)")
        let messages = await channel.broadcasts(event: "message")
        do {
          try await channel.subscribe()
          for await message in messages {
            show(message)
          }
        } catch {
          // subscribe() failed, or the task was cancelled.
        }
        await supabase.removeChannel(channel)
      }
  }
}
```

The socket closes when the last channel is removed, after
``RealtimeClientOptions/disconnectOnEmptyChannelsAfter``. Set that option to `.zero` to close it
at once.

### Idle socket

With ``RealtimeClientOptions/connectOnSubscribe`` on (the default), a subscribe opens the socket
when it is closed. When the last channel is removed, the socket stays open for
``RealtimeClientOptions/disconnectOnEmptyChannelsAfter`` (50 seconds by default) in case a new
channel comes, then closes. ``RealtimeClient/removeAllChannels()`` closes it at once.
