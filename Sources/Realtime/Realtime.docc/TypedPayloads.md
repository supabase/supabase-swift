# Typed Payloads

Decode broadcast, presence and row payloads into your own types, one element at a time.

## Overview

Every payload arrives as JSON. Each element type has a synchronous `decode(as:decoder:)`:
``BroadcastMessage/decode(as:decoder:)``, ``PostgresRow/decode(as:decoder:)``,
``PresenceEntry/decode(as:decoder:)`` and ``PresenceState/decode(as:decoder:ignoringUndecodable:)``.
A payload that does not decode throws ``RealtimeError/Kind-swift.struct/decoding`` at that call,
and the stream goes on. You decide what a bad element means.

```swift
for await message in channel.broadcasts(event: "cursor") {
  do {
    let cursor = try message.decode(as: Cursor.self)
    move(cursor)
  } catch {
    logger.warning("skipped a cursor: \(error)")
  }
}
```

The default decoder is `JSONDecoder.supabase()`, which reads Postgres dates.

### Typed postgres changes

``RealtimeChannel/postgresChanges(of:event:schema:table:filter:decoder:)`` binds a row type to
the stream. The binding is lazy: each ``TypedPostgresChange`` keeps the raw change, and
``TypedPostgresChange/row()`` decodes it when you call it.

```swift
let todos = channel.postgresChanges(of: Todo.self, table: "todos")
try await channel.subscribe()

for await change in todos {
  switch change.kind {
  case .insert, .update:
    if let todo = try? change.row() { upsert(todo) }
  case .delete:
    if let id = change.oldRecord?["id"]?.intValue { remove(id) }
  }
}
```

A delete has no record, so ``TypedPostgresChange/row()`` throws for it. Read the key from
``TypedPostgresChange/oldRecord``. It stays untyped on purpose: without `REPLICA IDENTITY FULL`,
or under row level security, it holds only the primary key columns.

The untyped ``RealtimeChannel/postgresChanges(event:schema:table:filter:select:)`` yields
``PostgresChange`` values. Decode their ``PostgresChange/record`` yourself, or read single
columns through ``PostgresRow/subscript(_:)``.

### Apps with default main actor isolation

A new Xcode 26 app target sets its default isolation to `MainActor`. In such a module, a plain
`struct Todo: Decodable` gets a conformance isolated to the main actor (SE-0466, SE-0470). The
decode calls above are synchronous and ask only for `Decodable`, so they accept that
conformance, and decoding on the main actor compiles as written.

Decoding anywhere else needs a conformance that is not isolated. Mark the type `nonisolated`:

```swift
nonisolated struct Tick: Decodable {
  let symbol: String
  let price: Double
}
```

Do this for every type you decode in a `@concurrent` function, on another actor, or in a task
group child, such as the aggregation loop in <doc:HighRateFeeds>. Without it, the compiler
rejects the call with an error about a main actor-isolated conformance.

This is also why the SDK has no typed broadcast stream and no stream that decodes for you. A
stream that yields `Row` values needs `Row: Sendable` and decodes off your actor, which a
main actor-isolated conformance cannot do.
