# Isolation

Why the client and its channels are actors, and how to call them from `@MainActor` code.

## Overview

``RealtimeClient`` and ``RealtimeChannel`` hold state that changes all the time: the socket, the
channels, the stream listeners and the token. Both types are actors, so the compiler checks
every access to that state, and you can call them from any isolation: the main actor, another
actor, or a task with no isolation.

Each client has one serial executor, and every channel it creates runs on that same executor.
The client and its channels are one isolation domain. A call from a channel to its client, or
the other way, does not switch threads.

### Calling from the main actor

From your code, every member is one `await`. The `await` goes to the client's executor and
comes back with the result:

```swift
@MainActor @Observable
final class RoomModel {
  var isOnline = false

  func refresh(_ channel: RealtimeChannel) async {
    isOnline = await channel.status.isSubscribed
  }
}
```

``RealtimeChannel/topic`` and ``RealtimeChannel/configuration`` never change, so they need no
`await`.

A stream method returns the stream after one `await`. The `for await` loop then runs on your
actor: in a SwiftUI `.task`, the loop body runs on the main actor and can write to your view
state directly. The elements are `Sendable` value types, so nothing has to be copied by hand.
For a feed with many elements per second, move the work off the main actor; see
<doc:HighRateFeeds>.

### The configure closure

``RealtimeClient/channel(_:configure:)`` runs its closure on the client's executor, so the
closure is `@Sendable`. Read the values it needs into local constants first:

```swift
let key = model.userID.uuidString
let channel = await supabase.channel("room:42") { config in
  config.presence.key = key
}
```

### Apps with default main actor isolation

A new Xcode app target sets its default isolation to `MainActor` (SE-0466). In such a module, a
plain `struct Status: Codable` gets `Codable` conformances isolated to the main actor (SE-0470).
Such a conformance works only on the main actor. What that means depends on where the SDK uses
it.

**Types you decode work as written.** Decoding happens where you call it. The `decode(as:)`
methods on ``BroadcastMessage``, ``PostgresRow``, ``PresenceEntry`` and ``PresenceState`` are
synchronous, and ``RealtimeChannel/postgresChanges(of:event:schema:table:filter:select:decoder:)``
runs on the caller's actor. Called from the main actor, they accept a main actor-isolated
conformance.

**Types you send must be `nonisolated`.** ``RealtimeChannel/broadcast(event:payload:encoder:)``
and ``RealtimeChannel/track(_:encoder:)`` encode the payload on the channel's executor, not on
the main actor. The compiler rejects a main actor-isolated `Encodable` conformance there, with
an error about a conformance used in an actor-isolated context. Mark the type `nonisolated`:

```swift
nonisolated struct Status: Codable {
  var name: String
  var typing: Bool
}

try await channel.track(Status(name: "Ana", typing: false))
```

The same holds for a type you decode off the main actor, for example in a `@concurrent`
function or a task group child, and for types the SDK calls from its own executor:
``WebSocketTransport``, ``WebSocketConnection``, and a `URLSessionDelegate` you pass to
``URLSessionWebSocketTransport``.

This is also why there is no stream that decodes for you. A stream that yields your row type
would decode on the channel's executor, which a main actor-isolated conformance cannot do.
``TypedPostgresChange`` keeps the raw change instead, and ``TypedPostgresChange/row()`` decodes
it where you call it. See <doc:TypedPayloads>.
