# ``Realtime``

Broadcast, presence and Postgres changes over one WebSocket, as async streams.

## Overview

``RealtimeClient`` owns the socket. Get it from `supabase.realtime`, or build one with
``RealtimeClient/init(url:options:)``. A ``RealtimeChannel`` is one topic on that socket. Both
types are actors, so you `await` their members (see <doc:Isolation>).

Every subscription is an `AsyncStream`. Open the streams, subscribe the channel, then iterate:

```swift
let channel = await supabase.channel("room:42")
let messages = await channel.broadcasts(event: "message")

do {
  try await channel.subscribe()
  for await message in messages {
    let chat = try message.decode(as: ChatMessage.self)
    print(chat.text)
  }
} catch {
  // A RealtimeError from subscribe() or decode(as:), or CancellationError.
}
await supabase.removeChannel(channel)
```

Streams never throw. A lost socket is a status, on ``RealtimeClient/statusChanges()``, and the
client reconnects and joins its channels again on its own. A channel that the server closes does
not join again; see <doc:ConnectionBehavior#When-the-server-closes-a-channel>. Calls with one
result, such as ``RealtimeChannel/subscribe()``, throw ``RealtimeError``.

## Topics

### Essentials

- <doc:Isolation>
- <doc:Lifetime>
- <doc:TypedPayloads>
- <doc:Presence>
- <doc:Auth>
- <doc:ConnectionBehavior>
- <doc:HighRateFeeds>
- <doc:PlatformNotes>
- <doc:CustomTransports>

### Client

- ``RealtimeClient``
- ``RealtimeClientOptions``
- ``RealtimeServerLogLevel``

### Channels

- ``RealtimeChannel``
- ``RealtimeChannelConfiguration``

### Status

- ``RealtimeClientStatus``
- ``RealtimeChannelStatus``
- ``RealtimeChannelEvent``
- ``HeartbeatEvent``

### Broadcast

- ``BroadcastMessage``
- ``BroadcastPayload``

### Postgres Changes

- ``PostgresChange``
- ``TypedPostgresChange``
- ``PostgresRow``
- ``PostgresColumn``
- ``PostgresChangeEvent``
- ``RealtimePostgresFilter``
- ``RealtimePostgresIsValue``
- ``RealtimePostgresFilterValue``

### Presence Tracking

- ``PresenceState``
- ``PresenceEntry``
- ``PresenceChange``

### Errors

- ``RealtimeError``

### Transport

- ``WebSocketTransport``
- ``WebSocketConnection``
- ``WebSocketFrame``
- ``WebSocketEvent``
- ``WebSocketCloseCode``
- ``URLSessionWebSocketTransport``
