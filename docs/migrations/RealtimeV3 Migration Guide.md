# Realtime V2 → V3 Migration Guide

Realtime V3 (`_Realtime`) is a greenfield redesign targeting Swift 6.0+ and iOS 17+.
Import it with `import _Realtime` (renamed to `import Realtime` at final release).

## Platform requirements

`_Realtime` requires iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+. Because the main
`Supabase` package still supports iOS 13+, the `realtimeV3` property cannot be exposed
on `SupabaseClient` directly within this repository while older platform support is kept.

For the time being, consumers on iOS 17+ can add `_Realtime` as a direct dependency:

```swift
.package(url: "https://github.com/supabase/supabase-swift", from: "x.y.z"),
// In your target dependencies:
.product(name: "_Realtime", package: "supabase-swift"),
```

A reference extension wiring `_Realtime` to `SupabaseClient` is provided as a template at
`docs/migrations/SupabaseClient+RealtimeV3.swift.template`. Copy it into your own target
that requires iOS 17+ and adjust access levels as needed.

## Quick-reference mapping

| V2 | V3 |
|----|-----|
| `import Realtime` | `import _Realtime` |
| `RealtimeClientV2(url:options:)` | `Realtime(url:apiKey:configuration:transport:)` |
| `client.channel("x", options: …)` | `realtime.channel("x") { $0.isPrivate = true }` |
| `await channel.subscribe()` | Implicit on first `broadcasts()` / `changes()` iteration |
| `await channel.unsubscribe()` | `try await channel.leave()` |
| `channel.broadcastStream(event:)` | `channel.broadcasts(of: T.self, event:)` |
| `await channel.broadcast(event:message:)` | `try await channel.broadcast(payload, as: event)` |
| `channel.postgresChange(.all, schema:table:filter:)` | `channel.changes(to: T.self, where: .eq(\.col, val))` |
| `channel.presenceChange()` | `channel.presence.diffs(T.self)` |
| `channel.track(state:)` | `try await channel.presence.track(state)` → `PresenceHandle` |
| `ObservationToken` / `subscription.cancel()` | Task cancellation ends `AsyncThrowingStream` iteration |
| `accessToken: () async -> String?` | `APIKeySource.dynamic { … }` |
| `any Error` at boundaries | `throws(RealtimeError)` everywhere |
| `RealtimeClientOptions.maxRetryAttempts` | `Configuration.reconnection: ReconnectionPolicy` |

## Key behavioural differences

### Explicit `leave()` — no auto-unsubscribe

V2 unsubscribed on `ObservationToken` deallocation. V3 requires an explicit `try await channel.leave()`.
The channel is shared within a `Realtime` instance — `leave()` tears it down for **all** holders.

### Channels shared by topic

`realtime.channel("room:1")` always returns the same actor regardless of how many times it is called.
One server-side subscription per topic per `Realtime` instance.

### `broadcast()` requires a joined channel

`try await channel.broadcast(…)` throws `.channelNotJoined` if the channel has not joined.
For one-shot sends without joining, use `realtime.httpBroadcast(topic:event:payload:)`.

### Stream lifecycle

V2 callback-based: `channel.onBroadcast(event:) { … }` returning `ObservationToken`.
V3 `AsyncThrowingStream`: `for try await msg in channel.broadcasts(of: T.self, event: "chat") { … }`.
Cancel by cancelling the enclosing `Task`.

### Typed errors

Every throwing API uses `throws(RealtimeError)`. Call sites can switch exhaustively:

```swift
do {
  try await channel.broadcast(msg, as: "event")
} catch let error as RealtimeError {
  switch error {
  case .channelNotJoined: ...
  case .disconnected: ...
  default: ...
  }
}
```

### `@RealtimeTable` macro

Use the `@RealtimeTable` macro to synthesize `RealtimeTable` conformance automatically:

```swift
@RealtimeTable(schema: "public", table: "messages")
struct Message: Codable, Sendable {
  var id: UUID
  var roomId: UUID  // mapped to "room_id" automatically
  var text: String
}

// Enables typed filters:
channel.changes(to: Message.self, where: .eq(\.roomId, id))
```
