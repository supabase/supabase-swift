## RealtimeV2 Migration Guide

In this guide we'll walk you through how to migrate from Realtime to the new RealtimeV2.

### Accessing the new client

Instead of `supabase.realtime` use `supabase.realtimeV2`.

### Observing socket connection status

Use `statusChange` property for observing socket connection changes, example:

```swift
for await status in supabase.realtimeV2.statusChange {
    // status: disconnected, connecting, or connected
}
```

If you don't need observation, you can access the current status using `supabase.realtimev2.status`.

### Observing channel subscription status

Use `statusChange` property for observing channel subscription status, example:

```swift
let channel = await supabase.realtimeV2.channel("public:messages")

Task {
    for status in await channel.statusChange {
        // status: unsubscribed, subscribing subscribed, or unsubscribing.
    }
}

await channel.subscribe()
```

If you don't need observation, you can access the current status uusing `channel.status`.

### Listening for Postgres Changes

Observe postgres changes using the new `postgresChanges(_:schema:table:filter)` methods.

```swift
let channel = await supabase.realtimeV2.channel("public:messages")

for await insertion in channel.postgresChange(InsertAction.self, table: "messages") {
    let insertedMessage = try insertion.decodeRecord(as: Message.self)
}

for await update in channel.postgresChange(UpdateAction.self, table: "messages") {
    let updateMessage = try update.decodeRecord(as: Message.self)
    let oldMessage = try update.decodeOldRecord(as: Message.self)
}

for await deletion in channel.postgresChange(DeleteAction.self, table: "messages") {
    struct Payload: Decodable {
        let id: UUID
    }

    let payload = try deletion.decodeOldRecord(as: Payload.self)
    let deletedMessageID = payload.id
}
```

If you wish to listen for all changes, use:

```swift
for change in channel.postgresChange(AnyAction.self, table: "messages") {
    // change: enum with insert, update, and delete cases.
}
```

### Tracking Presence

Use `track(state:)` method for tracking Presence.

```swift
let channel = await supabase.realtimeV2.channel("room")

await channel.track(state: ["user_id": "abc_123"])
```

Or use method that accepts a `Codable` value:

```swift
struct UserPresence: Codable {
    let userId: String
}

await channel.track(UserPresence(userId: "abc_123"))
```

Use `untrack()` for when done:

```swift
await channel.untrack()
```

### Listening for Presence Joins and Leaves

Use `presenceChange()` for obsering Presence state changes.

```swift
for await presence in channel.presenceChange() {
    let joins = try presence.decodeJoins(as: UserPresence.self) // joins is [UserPresence]
    let leaves = try presence.decodeLeaves(as: UserPresence.self) // leaves is [UserPresence]
}
```


### Pushing broadcast messages

Use `broadcast(event:message)` for pushing a broadcast message.

```swift
await channel.broadcast(event: "PING", message: ["timestamp": .double(Date.now.timeIntervalSince1970)])
```

Or use method that accepts a `Codable` value.

```swift
struct PingEventMessage: Codable {
    let timestamp: TimeInterval
}

try await channel.broadcast(event: "PING", message: PingEventMessage(timestamp: Date.now.timeIntervalSince1970))
```

### Listening for Broadcast messages

Use `broadcastStream()` method for observing broadcast events.

```swift
for await event in channel.broadcastStream(event: "PING") {
    let message = try event.decode(as: PingEventMessage.self)
}
```
