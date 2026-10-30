# Subscription Lifetime

Tie a subscription to a task: open the streams, subscribe, iterate, and remove the channel when
the task ends.

## Overview

A stream lives as long as the loop that iterates it. Leaving the loop, or cancelling the task
that runs it, ends the stream and removes its listener. The channel itself stays joined until
you call ``RealtimeChannel/unsubscribe()`` or ``RealtimeClient/removeChannel(_:)``. So the task
that iterates the streams also owns the channel, and removes it on the way out.

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
        let channel = await supabase.channel("room:\(roomID)")
        let incoming = await channel.broadcasts(event: "message")
        do {
          try await channel.subscribe()
          for await message in incoming {
            if let chat = try? message.decode(as: ChatMessage.self) {
              messages.append(chat)
            }
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

Open the streams before ``RealtimeChannel/subscribe()``. A stream gets the events that arrive
after the call that opened it returns, so a stream opened first sees everything from the join
on. Presence and Postgres changes streams also shape the join request; see
<doc:Lifetime#Streams-that-shape-the-join>.

### One stream per call

Each call to a stream method, such as ``RealtimeChannel/broadcasts(event:)`` or
``RealtimeChannel/statusChanges()``, opens a new, independent stream. Two consumers need two
calls.

An `AsyncStream` has one consumer. Iterate each stream from one task only; iterating the same
stream from two tasks at once is a programming error.

### Channel handles

``RealtimeClient/channel(_:configure:)`` returns the same ``RealtimeChannel`` for the same topic
until you remove it. The configuration is fixed when the channel is created. Asking for an
existing topic with a different configuration returns the existing channel and reports an
issue.

Dropping your reference does not leave the channel; the client keeps it in
``RealtimeClient/channels``. ``RealtimeClient/removeChannel(_:)`` leaves the topic and ends every
stream opened on the channel. Do not use a removed handle again: ask the client for a new
channel instead.

### Streams that shape the join

The server sends presence and Postgres changes only to a join that asks for them, so the
streams you open before ``RealtimeChannel/subscribe()`` decide what the join requests.

- A presence stream, ``RealtimeChannel/presenceStates()`` or
  ``RealtimeChannel/presenceChanges()``, must be open before ``RealtimeChannel/subscribe()``. On
  a channel that is joining or joined, the call reports an issue and returns a stream that has
  already finished.
- A Postgres changes stream opened on a joined channel makes the channel leave and join again
  with the new binding. ``RealtimeChannel/events()`` then yields
  ``RealtimeChannelEvent/resubscribed``. Open these streams first to join once.

Ending a Postgres changes stream removes its listener. The server binding stays until the
channel joins again.

### Rejoins and missed events

When the socket drops, the client connects again and joins every channel again on its own. A
channel goes back through ``RealtimeChannelStatus/subscribing(attempt:)`` to
``RealtimeChannelStatus/subscribed``, and ``RealtimeChannel/events()`` yields
``RealtimeChannelEvent/resubscribed``. When a join attempt fails, the channel waits in
``RealtimeChannelStatus/resubscribing(attempt:retryIn:lastError:)`` before the next one.

Events sent while the channel was not joined are lost. If your screen needs every row, load the
data again when ``RealtimeChannelEvent/resubscribed`` arrives:

```swift
.task(id: roomID) {
  let channel = await supabase.channel("room:\(roomID)")
  let changes = await channel.postgresChanges(table: "messages")
  let events = await channel.events()
  try? await channel.subscribe()

  await withTaskGroup { group in
    group.addTask {
      for await event in events where event == .resubscribed {
        await model.reload()
      }
    }
    group.addTask {
      for await change in changes {
        await model.apply(change)
      }
    }
  }
  await supabase.removeChannel(channel)
}
```
