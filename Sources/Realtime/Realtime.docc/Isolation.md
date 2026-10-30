# Isolation

Why the client is an actor, why channel reads are `async`, and how to call them from
`@MainActor` code.

## Overview

``RealtimeClient`` holds state that changes all the time: the socket, the channels, the stream
listeners and the token. The client is an actor, so the compiler checks every access to that
state, and you can call it from any isolation: the main actor, another actor, or a task with no
isolation.

The client owns the state of its channels too. A ``RealtimeChannel`` is a `Sendable` class that
holds no state of its own. It is a handle: each read, stream method and action goes to the
client actor. The client and its channels are one isolation domain, the client actor.

### Calling from the main actor

From your code, every read is one `await`. The `await` goes to the client actor and comes back
with the result:

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
`await`. Equality and hashing need none either. Two channels are equal only when they are the
same instance.

A stream method returns the stream after one `await`. The stream is registered when the call
returns, so it sees every event that your next action causes. The `for await` loop then runs on
your actor: in a SwiftUI `.task`, the loop body runs on the main actor and can write to your
view state directly. The elements are `Sendable` value types, so nothing has to be copied by
hand. For a feed with many elements per second, move the work off the main actor; see
<doc:HighRateFeeds>.

### The configure closure

``RealtimeClient/channel(_:configure:)`` runs its closure on the caller's actor, before the call
reaches the client. The closure is not `@Sendable`, so it can read your state directly:

```swift
let channel = await supabase.channel("room:42") { config in
  config.presence.key = model.userID.uuidString
}
```

### Apps with default main actor isolation

A new Xcode app target sets its default isolation to `MainActor` (SE-0466). In such a module, a
plain `struct Status: Codable` gets `Codable` conformances isolated to the main actor (SE-0470).
Such a conformance works only on the main actor. What that means depends on where the SDK uses
it.

**Types you decode work as written.** Decoding happens where you call it. The `decode(as:)`
methods on ``BroadcastMessage``, ``PostgresRow``, ``PresenceEntry`` and ``PresenceState`` are
synchronous, and ``TypedPostgresChange/row()`` runs on the caller's actor. Called from the main
actor, they accept a main actor-isolated conformance.

**Types you send work as written too.** ``RealtimeChannel/broadcast(event:payload:encoder:)``,
``RealtimeChannel/track(_:encoder:)`` and
``RealtimeChannel/httpSend(event:payload:encoder:timeout:)`` encode the payload on the caller's
actor, before the call goes to the client. Called from the main actor, they accept a main
actor-isolated `Encodable` conformance:

```swift
struct Status: Codable {
  var name: String
  var typing: Bool
}

try await channel.track(Status(name: "Ana", typing: false))
```

**Types used off the main actor must be `nonisolated`.** This holds for a type you decode or
encode off the main actor, for example in a `@concurrent` function or a task group child. It
also holds for types the SDK calls from its own isolation: ``WebSocketTransport``,
``WebSocketConnection``, and a `URLSessionDelegate` you pass to
``URLSessionWebSocketTransport``.

This is also why there is no stream that decodes for you. A stream that yields your row type
would decode on the client actor, which a main actor-isolated conformance cannot do.
``TypedPostgresChange`` keeps the raw change instead, and ``TypedPostgresChange/row()`` decodes
it where you call it. See <doc:TypedPayloads>.
