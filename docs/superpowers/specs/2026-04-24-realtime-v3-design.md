# Realtime v3 — Implementation Design

**Date:** 2026-04-24
**RFC:** [Linear project](https://linear.app/supabase/project/realtime-v3-idiomatic-swift-api-rfc-044c5935314f/overview)
**Full API spec:** [Linear document](https://linear.app/supabase/document/realtime-v3-full-api-specification-a825f8ba2f42)
**Status:** Approved for implementation

---

## Context

Greenfield redesign of the Realtime module in `supabase-swift`. The RFC spec is the source of truth for the public API surface. This document covers the implementation strategy: module structure, phasing, actor architecture, and testing approach. Backend assumptions from the RFC are treated as confirmed.

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Module delivery | Separate Swift package `Packages/_Realtime/` during dev; folded into main package at release | Lets the new package target Swift 6.0+ / iOS 17+ without bumping the main package floor prematurely |
| Temporary module name | `_Realtime` | Underscore signals unstable/transitional; renamed to `Realtime` at release |
| Platform floor | iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+ | Required for `@Observable` user integration; typed throws and actors are compiler-level |
| Swift language mode | Swift 6 (`swiftLanguageMode(.v6)`) | Enables typed throws (`throws(RealtimeError)`), strict concurrency |
| Phasing approach | 8 phases, linear, single coordinated release | Test infrastructure (Phase 2) lands early so all feature phases have deterministic tests |
| Release trigger | All 8 phases complete and fully functional | No partial releases |

---

## Module Structure

```
supabase-swift/
├── Sources/                        ← existing, untouched during development
├── Tests/                          ← existing, untouched during development
├── Packages/
│   └── _Realtime/                  ← new standalone Swift package
│       ├── Package.swift           — swift-tools-version: 6.0, iOS 17+
│       ├── Sources/
│       │   └── _Realtime/
│       │       ├── Error/
│       │       ├── Transport/
│       │       ├── Config/
│       │       ├── Client/
│       │       ├── Channel/
│       │       ├── Broadcast/
│       │       ├── Presence/
│       │       ├── Postgres/
│       │       ├── Macros/
│       │       └── Internal/       — vendored wire protocol (Phoenix message decoding)
│       └── Tests/
│           └── _RealtimeTests/
```

The main `supabase-swift` `Package.swift` adds a local dependency on `Packages/_Realtime` so the `Supabase` target and integration tests can import `_Realtime` without publishing.

At release:
- `Packages/_Realtime/Sources/_Realtime/` moves to `Sources/_Realtime/` (or `Sources/Realtime/` after old module is retired)
- `Packages/_Realtime/Tests/` moves to `Tests/_RealtimeTests/`
- `Packages/_Realtime/` is deleted
- Main `Package.swift` bumps to Swift 6.0+, iOS 17+, removes local package dependency, adds `_Realtime` target directly

---

## Package.swift for `Packages/_Realtime/`

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "_Realtime",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
    .tvOS(.v17),
    .watchOS(.v10),
    .visionOS(.v1),
  ],
  products: [
    .library(name: "_Realtime", targets: ["_Realtime"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-http-types.git", from: "1.3.0"),
    .package(url: "https://github.com/pointfreeco/swift-clocks", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.1.0"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.2.2"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.3.2"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
  ],
  targets: [
    .target(
      name: "_Realtime",
      dependencies: [
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "Clocks", package: "swift-clocks"),
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
      ]
    ),
    .testTarget(
      name: "_RealtimeTests",
      dependencies: [
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        "_Realtime",
      ]
    ),
  ]
)
```

---

## Phase Breakdown

### Phase 1 — Foundation

No actor, no connection. Pure types.

```
Sources/_Realtime/
  Error/
    RealtimeError.swift          — flat RealtimeError enum (all cases from §7 of spec), CloseReason
    RealtimeLogger.swift         — RealtimeLogger protocol, LogEvent, LogLevel, Category
  Transport/
    RealtimeTransport.swift      — RealtimeTransport + RealtimeConnection protocols, TransportFrame enum
    URLSessionTransport.swift    — production URLSession-based implementation
  Config/
    APIKeySource.swift           — APIKeySource enum: .literal(String), .dynamic(@Sendable () async throws -> String)
    ReconnectionPolicy.swift     — ReconnectionPolicy struct + .never, .exponentialBackoff, .fixed factories
    Configuration.swift          — Configuration struct: heartbeat, joinTimeout, leaveTimeout, broadcastAckTimeout,
                                   reconnection, disconnectOnEmptyChannelsAfter, handleAppLifecycle,
                                   protocolVersion, clock, headers, logger, decoder, encoder
```

### Phase 2 — Test Infrastructure

Enables deterministic tests for all subsequent phases.

```
Sources/_Realtime/
  Testing/
    InMemoryTransport.swift      — InMemoryTransport: RealtimeTransport; pair() -> (client, server)
    InMemoryConnection.swift     — InMemoryConnection: RealtimeConnection; server-side send + frame stream

Tests/_RealtimeTests/
  TransportTests.swift           — frames flow client→server and server→client correctly
```

`InMemoryTransport.pair()` is a public API in the main `_Realtime` target (not a separate test-helpers target) so callers can use it in their own tests — matching the RFC's intent.

### Phase 3 — `Realtime` Actor

```
Sources/_Realtime/
  Client/
    ConnectionStatus.swift       — ConnectionStatus struct + State enum (idle, connecting, connected,
                                   reconnecting, closed)
    Realtime.swift               — Realtime actor: init, connect(), disconnect(), status stream,
                                   updateToken(_:), channel(_:configure:), httpBroadcast
    HeartbeatManager.swift       — sends phx_heartbeat on interval, tracks RTT, fires on missed beats
    ReconnectManager.swift       — applies ReconnectionPolicy, drives reconnect loop with clock

Tests/_RealtimeTests/
  RealtimeClientTests.swift      — connect/disconnect, reconnect policy, heartbeat timeout, token rotation
```

### Phase 4 — `Channel` Actor

```
Sources/_Realtime/
  Channel/
    ChannelState.swift           — ChannelState enum: unsubscribed, joining, joined, leaving, closed(CloseReason)
    ChannelOptions.swift         — ChannelOptions, BroadcastOptions, ReplayOption
    Channel.swift                — Channel actor: join(), leave(), state stream, options (first-call-wins lock)
    ChannelRegistry.swift        — [String: Channel] cache inside Realtime; topic identity guarantee

Tests/_RealtimeTests/
  ChannelTests.swift             — join/leave, duplicate-topic identity, first-call-wins options,
                                   global leave tears down all streams with .channelClosed(.userRequested)
```

### Phase 5 — Broadcast

```
Sources/_Realtime/
  Broadcast/
    BroadcastMessage.swift       — BroadcastMessage: event, payload: JSONValue, receivedAt: Date
    Channel+Broadcast.swift      — broadcasts(of:event:) -> AsyncThrowingStream<T, RealtimeError>
                                   broadcasts() -> AsyncThrowingStream<BroadcastMessage, RealtimeError>
                                   broadcast(_:as:) async throws(RealtimeError)
                                   broadcast(_data:as:) async throws(RealtimeError)
  Broadcast/
    Realtime+HTTP.swift          — httpBroadcast(topic:event:payload:isPrivate:)
                                   httpBroadcast(_:[HttpBroadcastMessage]) batch form
                                   HttpBroadcastMessage struct

Tests/_RealtimeTests/
  BroadcastTests.swift           — delivery, fan-out to N subscribers, typed decode, HTTP path,
                                   .channelNotJoined when not joined, .disconnected during outage
```

### Phase 6 — Presence

```
Sources/_Realtime/
  Presence/
    PresenceHandle.swift         — PresenceHandle class: cancel() async throws(RealtimeError)
                                   debug IssueReporting warning on deinit without cancel
    PresenceState.swift          — PresenceState<T: Sendable>, PresenceDiff<T: Sendable>, PresenceKey typealias
    Presence.swift               — Presence struct: track(_:) -> PresenceHandle, observe(_:), diffs(_:)
                                   auto re-track on reconnect; tracks last state per live handle
    Channel+Presence.swift       — channel.presence computed property

Tests/_RealtimeTests/
  PresenceTests.swift            — track/untrack, snapshot + diffs, auto re-track on rejoin,
                                   multi-track (multiple metas per key), handle leak warning
```

### Phase 7 — Postgres Changes

```
Sources/_Realtime/
  Postgres/
    RealtimeTable.swift          — RealtimeTable protocol: schema, tableName, columnName(for:)
    Filter.swift                 — Filter<T: RealtimeTable> struct with static factories: eq, neq, gt, gte,
                                   lt, lte, in; UntypedFilter for escape hatch; wire encoding
    PostgresChange.swift         — PostgresChange<T> enum: insert(T), update(old: T, new: T), delete(old: T)
                                   internal decoding from Phoenix payload
    Channel+Postgres.swift       — changes(to:where:) -> AsyncThrowingStream<PostgresChange<T>, RealtimeError>
                                   inserts(into:where:), updates(of:where:), deletes(from:where:) convenience
                                   changes(schema:table:filter:) untyped overload -> PostgresChange<JSONValue>

Tests/_RealtimeTests/
  PostgresChangesTests.swift     — filter wire encoding, typed changes stream, untyped escape hatch,
                                   per-event convenience streams, insert/update/delete decoding
```

### Phase 8 — Macro + Integration

```
Packages/_RealtimeTableMacros/            — new standalone macro package
  Package.swift                           — declares macro target, depends on swift-syntax
  Sources/
    _RealtimeTableMacroPlugin/
      RealtimeTableMacro.swift            — @RealtimeTable macro implementation:
                                            synthesizes RealtimeTable conformance,
                                            schema/tableName static properties,
                                            columnName(for:) honoring CodingKeys

Sources/_Realtime/
  Macros/
    RealtimeTable+Macro.swift             — @attached(extension) macro declaration

Sources/Supabase/                         — main package (existing)
  SupabaseClient+Realtime.swift           — exposes realtime: Realtime property on SupabaseClient

Tests/IntegrationTests/                   — main package (existing)
  RealtimeV3IntegrationTests.swift        — real socket tests against local Supabase instance

docs/migrations/RealtimeV3 Migration Guide.md
```

---

## Actor Architecture

### Topology

```
Realtime (actor)
  ├── WebSocket connection (via RealtimeTransport / RealtimeConnection)
  ├── HeartbeatManager
  ├── ReconnectManager
  ├── ChannelRegistry: [topic: String → Channel actor]
  └── Channel (actor) — one per unique topic
        ├── Join/leave state machine
        ├── broadcastContinuations: [UUID → Continuation]
        ├── presenceContinuations:  [UUID → Continuation]
        └── postgresContinuations:  [UUID → Continuation]
```

`Realtime` receives raw `TransportFrame`s from `RealtimeConnection.frames`, decodes them using vendored Phoenix message parsing (from `Sources/_Realtime/Internal/`), and routes to the correct `Channel` by topic. Each `Channel` fans out to its registered continuations.

### Stream Fan-out Pattern

All three feature streams (broadcast, presence, postgres) use the same pattern inside the `Channel` actor:

```swift
// Registering a subscriber
func broadcasts() -> AsyncThrowingStream<BroadcastMessage, RealtimeError> {
    AsyncThrowingStream { continuation in
        let id = UUID()
        broadcastContinuations[id] = continuation
        continuation.onTermination = { [id] _ in
            Task { await self.broadcastContinuations.removeValue(forKey: id) }
        }
        Task { try await joinIfNeeded() }   // auto-join on first subscriber
    }
}

// Routing an incoming message
func deliver(_ msg: BroadcastMessage) {
    for cont in broadcastContinuations.values { cont.yield(msg) }
}
```

Typed streams (`broadcasts(of: T.self, event:)`) wrap the untyped stream, filtering by event name and decoding with `JSONDecoder`, surfacing decode failures as `RealtimeError.decoding(type:underlying:)`.

### Leave Semantics

`channel.leave()` after server ACK calls `.finish(throwing: RealtimeError.channelClosed(.userRequested))` on every live continuation (broadcast, presence, postgres), then removes the channel from `ChannelRegistry`. All active `for await` loops on that channel see the error immediately.

### Phoenix Wire Protocol

The existing Phoenix message encoding/decoding from `Sources/Realtime/RealtimeSerializer.swift` and `RealtimeMessageV2.swift` is vendored into `Sources/_Realtime/Internal/` (copied, not imported). This avoids a cross-target dependency on the old `Realtime` module.

---

## Testing Strategy

### Primary tool: `InMemoryTransport.pair()`

```swift
let clock = TestClock()
let (transport, server) = InMemoryTransport.pair()
let realtime = Realtime(
    url: testURL, apiKey: .literal("key"),
    configuration: .init(clock: clock),
    transport: transport
)
```

The `server` side exposes:
- `nextFrame() async -> TransportFrame` — awaits the next frame the client sends
- `send(_ frame: TransportFrame) async` — pushes a frame to the client's `.frames` stream
- `close(code:reason:)` — simulates server-initiated close

### Coverage per Phase

| Phase | Focus |
|-------|-------|
| 2 | Frames flow bidirectionally through InMemoryTransport |
| 3 | Connect, disconnect, reconnect with policy, heartbeat timeout via TestClock, token rotation retry |
| 4 | Join/leave ACK, duplicate-topic identity, first-call-wins options + debug warning, global leave |
| 5 | Broadcast delivery, N-subscriber fan-out, typed decode error, HTTP path, channelNotJoined |
| 6 | Track/untrack ACK, snapshot + incremental diffs, auto re-track on rejoin, multi-meta, leak warning |
| 7 | Filter wire strings, typed + untyped change streams, insert/update/delete payload decoding |
| 8 | @RealtimeTable macro expansion (compile-time), columnName(for:) with CodingKeys |

Snapshot testing via `InlineSnapshotTesting` for Phoenix message encoding/decoding, matching the existing project convention.

Integration tests (real socket, local Supabase) land in Phase 8 inside `Tests/IntegrationTests/` of the main package.
