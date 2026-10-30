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

try await channel.subscribe()
for await message in messages {
  let chat = try message.decode(as: ChatMessage.self)
  print(chat.text)
}
await supabase.removeChannel(channel)
```

Streams never throw. A lost socket or a lost join is a status, on
``RealtimeClient/statusChanges()`` and ``RealtimeChannel/statusChanges()``, and the client
recovers on its own. Calls with one result, such as ``RealtimeChannel/subscribe()``, throw
``RealtimeError``.

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
