# Subscription Lifetime

Tie a subscription to a task: make the streams, subscribe, iterate, and remove the channel when
the task ends.

## Overview

A stream lives as long as the loop that iterates it. Leaving the loop, or cancelling the task
that runs it, removes the stream's listener. The channel itself stays joined until you call
``RealtimeChannel/unsubscribe()`` or ``RealtimeClient/removeChannel(_:)``. So the task that
iterates the streams also owns the channel, and removes it on the way out.

### One task per screen

In SwiftUI, `.task(id:)` covers the whole lifecycle. It starts when the view appears, is
cancelled when the view goes away or the id changes, and starts again for a new id.

```swift
struct RoomView: View {
  let roomID: UUID
  @State private var messages: [ChatMessage] = []

  var body: some View {
    List(messages) { Text($0.text) }
      .task(id: roomID) {
        let channel = supabase.channel("room:\(roomID)")
        let incoming = channel.broadcasts(event: "message")
        do {
          try await channel.subscribe()
          for await message in incoming {
            if let chat = try? message.decode(as: ChatMessage.self) { messages.append(chat) }
          }
        } catch {
          // A RealtimeError from subscribe(), or CancellationError.
        }
        await supabase.removeChannel(channel)
      }
  }
}
```

The loop ends when the task is cancelled, so the code after it runs. There is no `onDisappear`
and no stored task to cancel. ``RealtimeClient/removeChannel(_:)`` does not check for
cancellation, so it still leaves the channel after the task is cancelled.

Make the streams before ``RealtimeChannel/subscribe()``. A stream registers its listener when
the call returns, so it sees everything from the join on.

### One stream per call

Each call to a stream-returning API, such as ``RealtimeChannel/broadcasts(event:)`` or
``RealtimeChannel/statusChanges``, makes a new, independent stream. Two consumers need two calls.

Iterate a stream value once. Two iterators made from the same value split its elements between
them, so each one sees only part of the feed.

### Channel handles

``RealtimeClient/channel(_:configure:)`` returns the same ``RealtimeChannel`` for the same topic
until you remove it. Dropping your reference does not leave the channel. After
``RealtimeClient/removeChannel(_:)`` the handle is dead: its streams finish, a stream made on it
later finishes at once, and its ``RealtimeChannel/subscribe()`` throws. Ask the client for a
new one.

Releasing the ``RealtimeClient`` closes the socket and finishes every stream of the client and of
its channels. A status stream yields a last ``RealtimeConnectionStatus/disconnected(_:)`` or
``RealtimeChannelStatus/unsubscribed`` first.

A ``RealtimeChannel/postgresChanges(event:schema:table:filter:select:)`` call adds a binding to
the channel. The binding stays until the channel is removed, even after its stream ends.

### Rejoins and missed events

When the socket drops or the server closes the channel, the client joins again on its own. The
channel's status goes through ``RealtimeChannelStatus/resubscribing(attempt:retryIn:lastError:)``
and back to ``RealtimeChannelStatus/subscribed``, and ``RealtimeChannel/events`` yields
``RealtimeChannelEvent/resubscribed``.

Events sent while the channel was not joined are lost. If your screen needs every row, re-fetch
the data when ``RealtimeChannelEvent/resubscribed`` arrives:

```swift
.task(id: roomID) {
  let channel = supabase.channel("room:\(roomID)")
  let changes = channel.postgresChanges(table: "messages")
  let events = channel.events
  try? await channel.subscribe()
  await withTaskGroup(of: Void.self) { group in
    group.addTask {
      for await event in events {
        if case .resubscribed = event { await model.reload() }
      }
    }
    group.addTask {
      for await change in changes { await model.apply(change) }
    }
  }
  await supabase.removeChannel(channel)
}
```

The client also joins again, and yields ``RealtimeChannelEvent/resubscribed``, when a new
postgres changes stream or the first presence stream is made on a joined channel. Make those
streams before ``RealtimeChannel/subscribe()`` to join once.
