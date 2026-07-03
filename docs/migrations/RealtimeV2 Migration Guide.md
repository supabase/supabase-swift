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

If you don't need observation, you can access the current status using `supabase.realtimeV2.status`.

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

If you don't need observation, you can access the current status using `channel.status`.

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

#### Filtering changes

Pass a `RealtimePostgresFilter` to receive only the changes matching a
`column=operator.value` expression. In addition to `eq`/`neq`/`gt`/`gte`/`lt`/`lte`/`in`,
the following operators are supported: `like`, `ilike`, `match`, `imatch`, `is`
and `isDistinct`. Any single condition can be negated with `.not(_:)`, and
multiple conditions can be combined with `.and(_:)` (applied server-side as a
logical `AND`).

```swift
// amount=gt.100,status=not.in.(draft),title=like.%foo%
for await update in channel.postgresChange(
    UpdateAction.self,
    table: "orders",
    filter: .and([
        .gt("amount", value: 100),
        .not(.in("status", values: ["draft"])),
        .like("title", value: "%foo%"),
    ])
) {
    // ...
}
```

Values containing reserved characters (`,`, `(`, `)`, `"`, `\`) or surrounding
whitespace are automatically double-quoted and escaped PostgREST-style.

#### Selecting columns

Use `select` to receive only a subset of columns instead of the full row. This
reduces payload size (helpful for large `bytea`/`jsonb` columns). The listed
columns must be selectable by the subscribing role, and an explicit `schema` and
`table` are required.

```swift
for await change in channel.postgresChange(
    AnyAction.self,
    table: "users",
    select: ["id", "first_name"]
) {
    // change payloads only contain { id, first_name }
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

Use `presenceChange()` for observing Presence state changes.

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

### Knowing when the replication connection is ready

Opt in with `broadcast.replicationReady` when creating the channel to have the
server emit a `system` event once the Postgres replication connection backing
the channel is established and ready to stream changes. The notification arrives
through the existing `onSystem`/`system()` API — `status == .ok` means the
connection is ready (message `"Replication connection established"`).

```swift
let channel = supabase.channel("room") {
    $0.broadcast.replicationReady = true
}

Task {
    for await message in channel.system() {
        if message.status == .ok {
            // Replication connection is ready.
        }
    }
}

await channel.subscribe()
```
