# ``Realtime``

Broadcast, presence and Postgres changes over one WebSocket, as async streams.

## Overview

``RealtimeClient`` owns the socket. Get it from `supabase.realtime`, or build one with
``RealtimeClient/init(url:options:)``. A ``RealtimeChannel`` is one topic on that socket. Every
subscription is a ``RealtimeStream``: make the stream, subscribe the channel, iterate.

```swift
let channel = supabase.channel("room:42")
let messages = channel.broadcasts(event: "message")

try await channel.subscribe()
for await message in messages {
  let chat = try message.decode(as: ChatMessage.self)
  print(chat.text)
}
await supabase.removeChannel(channel)
```

Streams never throw. A lost socket or a lost join is a status, on
``RealtimeClient/statusChanges`` and ``RealtimeChannel/statusChanges``, and the client recovers
on its own. Calls with a bounded result, such as ``RealtimeChannel/subscribe()``, throw
``RealtimeError``.

## Topics

### Essentials

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
- ``BackoffPolicy``
- ``RealtimeServerLogLevel``

### Channels

- ``RealtimeChannel``
- ``RealtimeChannelConfiguration``
- ``RealtimeStream``

### Status

- ``RealtimeConnectionStatus``
- ``RealtimeChannelStatus``
- ``RealtimeChannelEvent``
- ``RealtimeSystemMessage``
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

- ``RealtimePresence``
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
