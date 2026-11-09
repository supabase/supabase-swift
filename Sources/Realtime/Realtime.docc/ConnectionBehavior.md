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
``RealtimeChannelStatus``. Both reads are `async`. Each one is also a stream, ``RealtimeClient/statusChanges()`` and
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

``RealtimeClient/disconnect(code:reason:)`` is not a drop. It makes every subscribed channel
``RealtimeChannelStatus/unsubscribed``, and the channels stay registered. The next
``RealtimeClient/connect()`` does not join them again. Call ``RealtimeChannel/subscribe()`` on
each one; ``RealtimeChannel/events()`` then yields ``RealtimeChannelEvent/resubscribed``.

### When the server closes a channel

The server can end a channel while the socket stays up, for example when the token expires. What
follows depends on the message:

- After a channel error (`phx_error`), the channel joins again on its own. Its status becomes
  ``RealtimeChannelStatus/resubscribing(attempt:retryIn:lastError:)`` with a
  ``RealtimeError/Kind-swift.struct/channelError`` error, and the rejoin waits 1, 2 and 5
  seconds, then every 10 seconds, between attempts. Pushes that wait for a reply throw the same
  error. When the rejoin succeeds, ``RealtimeChannel/events()`` yields
  ``RealtimeChannelEvent/resubscribed``. A `phx_error` during a join counts as a failed attempt,
  so ``RealtimeChannel/subscribe()`` keeps waiting.
- After a close (`phx_close`), the channel does not join again. Its status becomes
  ``RealtimeChannelStatus/unsubscribed``, the client removes the channel, and every stream on it
  ends. Your `for await` loops end. The handle is spent, as after
  ``RealtimeClient/removeChannel(_:)``: its actions throw
  ``RealtimeError/Kind-swift.struct/channelRemoved``. To keep receiving events, ask the client
  for a new channel and subscribe it. Watch ``RealtimeChannel/statusChanges()`` for
  ``RealtimeChannelStatus/unsubscribed`` if your screen must stay live.

### Heartbeat and liveness

The client sends a heartbeat every ``RealtimeClient/Configuration/heartbeatInterval`` (25 seconds by
default). When the next heartbeat is due and the server has not answered the last one, the
client closes the socket and reconnects. So a dead socket is found within two intervals. When
the app returns to the foreground, a liveness probe finds it sooner; see
<doc:ConnectionBehavior#Background-and-foreground-on-iOS>.
``RealtimeClient/heartbeats()`` reports each step, with the round-trip latency of each answer.
It is an event stream: it reports the steps after the call and never replays an earlier one.

The heartbeat runs on ``RealtimeClient/Configuration/clock``, a `ContinuousClock` by default. That
clock keeps counting while the device sleeps, so after a long sleep the next heartbeat is due at
once.

### Background and foreground on iOS

The client never disconnects when the app goes to the background. iOS suspends the app soon
after, and may close the socket while it is suspended. Disconnecting first gains nothing:

- A short trip to the background, such as a share sheet or a phone call, would cost a full
  reconnect, a join of every channel, and a presence leave and join that everyone else sees.
- A suspended app cannot finish a clean leave without a background task.

When the app comes back, the client recovers. With ``RealtimeClient/Configuration/observesAppLifecycle``
on (the default on iOS, macOS, tvOS and visionOS), the client checks the socket on foreground:

- If it is waiting before a reconnect attempt, it tries again at once.
- If the socket was connected before the app went to the background and is now closed, it
  connects and joins every channel again.
- If the socket looks open, it sends a heartbeat at once as a liveness probe. When the server
  does not answer within 5 seconds, the client closes the socket and reconnects without waiting
  out a backoff. A suspended app often leaves the socket dead, so this finds it in seconds
  instead of after the next heartbeat.

In each case where the client connects again, the channels join again and yield
``RealtimeChannelEvent/resubscribed``.

On macOS the signals are the Mac going to sleep and waking, because a Mac app that loses focus
keeps its connection.

### Network changes

With ``RealtimeClient/Configuration/monitorsNetworkPath`` on (the default on iOS, macOS, tvOS and
visionOS), the client watches the network path. When the path becomes satisfied while the client
is waiting before a reconnect attempt, it tries again at once instead of sleeping out the rest of
the wait. A path that flaps in bad reception cannot start an attempt per report: a hint never
starts an attempt less than 2 seconds after the last one started, and a hint that comes sooner
waits until that time. The client never waits for this hint: it keeps retrying on its backoff
schedule when the path monitor reports no network.

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
``RealtimeClient/Configuration/disconnectOnEmptyChannelsAfter``. Set that option to `.zero` to close it
at once.

### Idle socket

With ``RealtimeClient/Configuration/connectOnSubscribe`` on (the default), a subscribe opens the socket
when it is closed. When the last channel is removed, the socket stays open for
``RealtimeClient/Configuration/disconnectOnEmptyChannelsAfter`` (50 seconds by default) in case a new
channel comes, then closes. ``RealtimeClient/removeAllChannels()`` closes it at once.
