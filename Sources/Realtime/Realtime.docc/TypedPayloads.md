# Typed Payloads

Decode broadcast, presence and row payloads into your own types, one element at a time.

## Overview

Every payload arrives as JSON. Each element type has a synchronous `decode(as:decoder:)`:
``BroadcastMessage/decode(as:decoder:)``, ``PostgresRow/decode(as:decoder:)``,
``PresenceEntry/decode(as:decoder:)`` and
``PresenceState/decode(as:decoder:ignoringUndecodable:)``. A payload that does not decode
throws a ``RealtimeError`` of kind ``RealtimeError/Kind-swift.struct/decoding`` at that call, and
the stream goes on. You decide what a bad element means.

```swift
for await message in await channel.broadcasts(event: "cursor") {
  do {
    let cursor = try message.decode(as: Cursor.self)
    move(cursor)
  } catch {
    logger.warning("Skipped a cursor: \(error)")
  }
}
```

The default decoder for broadcasts and rows is the one the SDK uses for server responses. It
reads Postgres dates.

### Typed Postgres changes

``RealtimeChannel/postgresChanges(of:event:schema:table:filter:select:decoder:)`` binds a row
type to the stream. The binding is lazy: each ``TypedPostgresChange`` keeps the raw change, and
``TypedPostgresChange/row()`` decodes it when you call it. A row that does not decode never
drops the change or ends the stream.

```swift
let todos = await channel.postgresChanges(of: Todo.self, table: "todos")
try await channel.subscribe()

for await change in todos {
  switch change.kind {
  case .insert, .update:
    if let todo = try? change.row() { upsert(todo) }
  case .delete:
    if let id = change.oldRecord?["id"]?.intValue { remove(id) }
  default:
    break
  }
}
```

A delete has no record, so ``TypedPostgresChange/row()`` throws for it. Read the key from
``TypedPostgresChange/oldRecord``. It stays untyped on purpose: without `REPLICA IDENTITY FULL`,
or under row level security, it holds only the primary key columns.

``PostgresChange/Kind-swift.struct`` is an open set, so a `switch` over it needs a `default`
branch.

The untyped ``RealtimeChannel/postgresChanges(event:schema:table:filter:select:)`` yields
``PostgresChange`` values. Decode their ``PostgresChange/record`` yourself, or read single
columns through ``PostgresRow/subscript(_:)``.

### Apps with default main actor isolation

In a module whose default isolation is `MainActor`, a plain `struct Todo: Decodable` gets a
conformance isolated to the main actor. The decode calls above are synchronous and run where you
call them, so decoding on the main actor compiles as written.

Decoding anywhere else needs a conformance that is not isolated. Mark the type `nonisolated`:

```swift
nonisolated struct Tick: Decodable {
  let symbol: String
  let price: Double
}
```

Do this for every type you decode in a `@concurrent` function, on another actor, or in a task
group child, such as the loop in <doc:HighRateFeeds>. Do it also for every type you send with
``RealtimeChannel/broadcast(event:payload:encoder:)`` or ``RealtimeChannel/track(_:encoder:)``,
because the channel encodes it on its own executor. <doc:Isolation> explains why.
