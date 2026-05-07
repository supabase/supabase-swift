# Realtime v3 — Idiomatic Swift API Proposal

> Status: Design locked after grill-through. Greenfield design — no consideration
> given to V2 compatibility or other Supabase SDKs. Targets Swift 6.2+.
> Breaking changes accepted.

## Design Principles

1. **Explicit lifecycle.** Resources are acquired and released explicitly. No
   auto-cleanup on `deinit`, no magic based on reference counting. If you
   joined a channel, you call `leave()` when you're done.
2. **Type‑safety through the language.** Channels, events, presences, and
   Postgres tables are generic. The compiler rejects the wrong payload type.
3. **`AsyncSequence` is the canonical surface.** Closures appear only where
   they unlock a behavior a sequence cannot express.
4. **Observation‑native.** Clean integration with `@Observable` and SwiftUI.
5. **Typed throws throughout.** `throws(RealtimeError)` at every boundary.
6. **Resilient by default.** Automatic reconnection with pluggable policies;
   transparent re‑joining of channels and presences; token refresh.
7. **Explicit, injectable transport and clock.** Deterministic unit tests
   without real sockets or real wall‑clock time.
8. **No singletons.** Multiple `Realtime` instances coexist with zero shared
   state.

---

## 30‑Second Tour

```swift
import Realtime

let realtime = Realtime(
  url: URL(string: "wss://project.supabase.co/realtime/v1")!,
  apiKey: .literal("anon-key")
)

let channel = realtime.channel("room:42")

// Optional: register postgres tokens BEFORE subscribe.
let inserts = channel.inserts(into: Message.self, where: .eq(\.roomId, 42))

// Single explicit join.
let sub = try await channel.subscribe()

// Typed broadcast receive.
Task {
  for try await msg in sub.broadcasts(of: ChatMessage.self, event: "chat") {
    render(msg)
  }
}

// Postgres consumption.
Task {
  for try await row in sub.events(for: inserts) {
    append(row)
  }
}

// Untyped raw feed (the AsyncSequence conformance).
Task {
  for try await frame in sub {
    // frame: PhoenixMessage — broadcast / postgres_changes / presence_diff / ...
  }
}

// Send (only available on the subscription — Channel has no broadcast method).
try await sub.broadcast(ChatMessage(text: "hi"), as: "chat")

// Explicit release when done.
try await sub.leave()
```

One-shot send without joining:

```swift
try await realtime.httpBroadcast(
  topic: "room:42", event: "chat",
  payload: ChatMessage(text: "hi")
)
```

That's the mental model:

- **Channels are factories.** `realtime.channel(topic)` returns a handle for
  registering postgres tokens and triggering `subscribe()`. Nothing else.
- **`subscribe()` returns a `ChannelSubscription`.** All consumption (typed and
  untyped), all sending, and presence live on the subscription. The type
  system enforces "you must subscribe before doing anything live."
- **Postgres changes are register-then-subscribe.** The Phoenix wire forces it;
  the API reflects it. Tokens are reusable across `leave()` cycles.
- **One `phx_join` per topic.** All pending tokens land in that single join.

Everything below is elaboration.

---

## 1. Client Construction

```swift
public final actor Realtime: Sendable {
  public init(
    url: URL,
    apiKey: APIKeySource,
    configuration: Configuration = .default,
    transport: any RealtimeTransport = URLSessionTransport()
  )
}
```

### 1.1 `APIKeySource` separates static keys from rotating auth

```swift
public enum APIKeySource: Sendable {
  case literal(String)
  /// Called on connect and when the server rejects with `token_expired`.
  /// See §6.3 for mid-session rotation.
  case dynamic(@Sendable () async throws -> String)
}
```

### 1.2 Configuration

```swift
public struct Configuration: Sendable {
  public var heartbeat: Duration = .seconds(25)
  public var joinTimeout: Duration = .seconds(10)
  public var leaveTimeout: Duration = .seconds(10)
  public var broadcastAckTimeout: Duration = .seconds(5)
  public var reconnection: ReconnectionPolicy = .exponentialBackoff(
    initial: .seconds(1), max: .seconds(30), jitter: 0.2
  )
  public var disconnectOnEmptyChannelsAfter: Duration = .seconds(50)
  public var handleAppLifecycle: Bool = .automaticDefault
  public var protocolVersion: RealtimeProtocolVersion = .v2
  public var clock: any Clock<Duration> = ContinuousClock()
  public var headers: HTTPFields = [:]
  public var logger: (any RealtimeLogger)? = nil
  public var decoder: JSONDecoder = .iso8601
  public var encoder: JSONEncoder = .iso8601

  public static let `default` = Configuration()
}
```

`disconnectOnEmptyChannelsAfter` is an idle‑socket timeout: when the last
live channel has left, the socket stays open for this duration in case a new
channel joins, avoiding reconnect churn. `.zero` for immediate close.

---

## 2. Channels

### 2.1 Identity and lifecycle

```swift
public extension Realtime {
  /// Returns the `Channel` for `topic`. Shared by topic — two callers asking
  /// for the same topic receive the same underlying actor.
  ///
  /// The channel joins lazily on the first subscribe. The caller must call
  /// `leave()` to unsubscribe; `deinit` does NOT unsubscribe.
  func channel(
    _ topic: String,
    configure: (inout ChannelOptions) -> Void = { _ in }
  ) -> Channel
}

public final actor Channel: Sendable {
  public var topic: String { get }
  public var options: ChannelOptions { get }
  public var state: AsyncStream<ChannelState> { get }

  /// Explicit join. Returns a `ChannelSubscription` — the surface for all
  /// post-join interaction (consumption, sending, presence). Idempotent:
  /// calling while joined returns an equivalent subscription value; concurrent
  /// calls before join await the same in-flight join.
  ///
  /// Postgres-change registrations made before this call are baked into the
  /// `phx_join` payload (see §5). After the call returns, registration of
  /// new tokens throws `.cannotRegisterAfterJoin` until the next `leave()`.
  public func subscribe() async throws(RealtimeError) -> ChannelSubscription

  /// Convenience for callers who don't currently hold a subscription value
  /// (e.g., a different feature on the same shared topic). Equivalent to
  /// `subscribe().leave()` but does not require fetching the subscription.
  public func leave() async throws(RealtimeError)
}

/// The post-join surface. Iterating directly yields the raw Phoenix message
/// stream — every frame received on this channel, with no SDK-side filtering.
/// Methods refine into typed views for broadcasts, postgres changes, and
/// presence. Holds the only handle for sending broadcasts.
public struct ChannelSubscription: AsyncSequence, Sendable {
  public typealias Element = PhoenixMessage

  /// Raw iteration — every Phoenix frame on this channel, including
  /// `broadcast`, `postgres_changes`, `presence_diff`, `presence_state`,
  /// `system`, `phx_reply`, `phx_close`, and `phx_error`. The SDK still
  /// consumes these internally (ack correlation, lifecycle); raw consumers
  /// observe a copy. Fan-out: each iteration is independent.
  public func makeAsyncIterator() -> AsyncIterator

  // Typed views (§3, §5, §4) — see the relevant sections for full signatures.
  public func broadcasts<T: Decodable & Sendable>(of type: T.Type, event: String)
    -> AsyncThrowingStream<T, RealtimeError>
  public func events<T, E>(for token: ChangeRegistration<T, E>)
    -> AsyncThrowingStream<E.Element, RealtimeError>
  public var presence: Presence { get }

  // Sending (§3.2) — only available post-subscribe; type system enforces it.
  public func broadcast<T: Encodable & Sendable>(_ payload: T, as event: String)
    async throws(RealtimeError)
  public func broadcast(_ data: Data, as event: String) async throws(RealtimeError)

  /// Explicit unsubscribe. Global (§2.3); awaits server ACK. After leave,
  /// this subscription is invalidated — methods throw `.channelClosed`.
  /// Tokens registered on the underlying channel remain reusable for the
  /// next `subscribe()`.
  public func leave() async throws(RealtimeError)
}

public struct PhoenixMessage: Sendable {
  /// Phoenix join reference correlating this frame to its `phx_join`. `nil`
  /// for frames that predate the current join (rare).
  public let joinRef: String?

  /// Phoenix message reference for request/reply correlation. Set on
  /// pushes the SDK sent and on the matching `phx_reply`. `nil` for
  /// server-pushed events (`broadcast`, `postgres_changes`, etc.).
  public let ref: String?

  /// Channel topic this frame belongs to. Always matches the subscription's
  /// channel topic for `ChannelSubscription` iterators; included on the
  /// struct so consumers that hand `PhoenixMessage` values across boundaries
  /// (logging, debugging, multi-topic aggregation) keep the routing key.
  public let topic: String

  /// Server-side event name. Includes user-level events (`"broadcast"`,
  /// `"postgres_changes"`, `"presence_diff"`, `"presence_state"`, `"system"`)
  /// and Phoenix internals (`"phx_reply"`, `"phx_close"`, `"phx_error"`).
  public let event: String

  /// Raw payload as received. JSON for text frames, `Data` for binary
  /// (Phoenix v2 broadcast).
  public let payload: PhoenixPayload

  /// Local receipt timestamp.
  public let receivedAt: Date
}

public enum PhoenixPayload: Sendable {
  case json(JSONValue)
  case binary(Data)
}
```

Key invariants:

- **Topic identity.** `realtime.channel("x")` always returns the same actor.
  One server-side subscription per topic per `Realtime` instance.
- **No auto-unsubscribe.** Dropping a `Channel` or `ChannelSubscription` does
  nothing. Explicit `leave()` is the only way.
- **`subscribe()` is the only join path.** No lazy-join via iteration. The
  WebSocket opens lazily on the first `subscribe()` (§6.1).
- **Postgres tokens register before join.** `channel.changes(...)`,
  `channel.inserts(...)`, etc. mutate channel state and return tokens. Calling
  these *after* the channel has joined throws `.cannotRegisterAfterJoin`. After
  `leave()`, registration is allowed again — tokens are reusable across
  subscribe cycles. (§5)
- **Sending is only available on a subscription.** Type-level gate: there is
  no `Channel.broadcast(...)` method. For one-shot sends without joining, use
  `realtime.httpBroadcast` (§3.3).
- **Multiple `subscribe()` calls return equivalent subscriptions.** All point
  at the same backing channel state; any subscription's `leave()` ends the
  channel for every holder of the topic.
- **Leaked-channel warning.** When `Realtime` deinits with channels that
  have been joined but never left, an `IssueReporting` warning fires in
  debug builds. Release builds silently rely on server-side timeouts.

### 2.2 Channel options are locked at creation

```swift
public struct ChannelOptions: Sendable {
  public var isPrivate: Bool = false
  public var broadcast: BroadcastOptions = .init()
  public var presenceKey: String? = nil
}

public struct BroadcastOptions: Sendable {
  public var acknowledge: Bool = false
  public var receiveOwnBroadcasts: Bool = false
  public var replay: ReplayOption? = nil
}

public struct ReplayOption: Sendable {
  public var since: Date
  public var limit: Int?
}
```

Options are applied on the first `channel(topic)` call. **A later call with a
different `configure` closure is ignored** — the first call wins. An
`IssueReporting` warning fires in debug. The returned `Channel.options`
reflects the effective options.

### 2.3 `leave()` semantics (shared-handle model)

- `leave()` is **global**: it tears down the subscription for every holder of
  the same topic. Other holders' active streams terminate by throwing
  `RealtimeError.channelClosed(.userRequested)`.
- `leave()` is **await-to-ack**: it returns only after the server ACKs
  `phx_leave`. On transport failure or timeout, it throws.
- A **pipelined re-acquire** is safe: if `realtime.channel("x")` is called
  while a leave for `"x"` is in flight, the caller gets a fresh `Channel`
  whose join is queued behind the pending leave. Same-topic churn is
  transparent.

> **Topic ownership convention.** Because `leave()` is global, coincidental
> sharing of the same topic by unrelated features can tear down each
> other's streams. Topics should be namespaced by feature
> (`"chat:room:42"`, not `"room:42"`), or routed through a single owner.
> Document loudly in the user guide.

### 2.4 Channel state

```swift
public enum ChannelState: Sendable, Equatable {
  case unsubscribed
  case joining
  case joined
  case leaving
  case closed(CloseReason)
}

public enum CloseReason: Sendable, Equatable {
  case userRequested          // someone called leave()
  case serverClosed(code: Int, message: String?)
  case timeout
  case unauthorized
  case policyViolation(String)
  case transportFailure       // reconnection policy gave up
}
```

---

## 3. Broadcast

All broadcast surfaces — typed receiving, typed sending, and the untyped
iteration over the raw Phoenix feed — live on `ChannelSubscription`. The
type system enforces "you must have subscribed before consuming or sending."

### 3.1 Receiving

```swift
public extension ChannelSubscription {
  /// Typed event stream — decodes each broadcast message's payload to `T`,
  /// filtered to a single event name. Fan-out: each call returns an
  /// independent stream; multiple iterators observe every matching message.
  func broadcasts<T: Decodable & Sendable>(
    of type: T.Type,
    event: String
  ) -> AsyncThrowingStream<T, RealtimeError>
}

// Untyped iteration is the AsyncSequence conformance on ChannelSubscription
// itself (§2.1). Element is `PhoenixMessage`, which spans broadcasts,
// postgres_changes, presence_diff, and other channel-level events. To filter
// to broadcasts only, match on `event == "broadcast"` and decode `payload`
// manually — but the typed `broadcasts(of:event:)` method is the recommended
// path.
```

Streams pause silently during reconnection and resume on rejoin. Gaps are
inherent in fire-and-forget pub/sub and not surfaced — callers who care
correlate against `channel.state`.

Backpressure: each subscription has an **unbounded** buffer. A slow consumer
will accumulate pending messages and eventually OOM under sustained lag. A
`SlowConsumerPolicy` knob may be added later without breaking source.

### 3.2 Sending

```swift
public extension ChannelSubscription {
  /// Sends a broadcast. Behavior depends on `ChannelOptions.broadcast.acknowledge`:
  /// - `false` (default): fire-and-forget; returns after the frame is queued.
  /// - `true`: awaits server ack; throws on timeout (`broadcastAckTimeout`).
  ///
  /// Throws `.channelClosed` if `leave()` has been called on this or any
  /// other holder of the topic. Throws `.disconnected` if the socket is down
  /// — no queuing.
  func broadcast<T: Encodable & Sendable>(
    _ payload: T,
    as event: String
  ) async throws(RealtimeError)

  /// `Data` bypasses encoding and ships as a binary frame (Phoenix v2).
  func broadcast(_ data: Data, as event: String) async throws(RealtimeError)
}
```

Type-level guarantee: there is no `Channel.broadcast(...)`. To send, callers
must first `await channel.subscribe()`. The previous `.channelNotJoined`
runtime error is gone — the situation is unrepresentable.

### 3.3 HTTP one-shot broadcast

For senders that don't need a subscription, `realtime.httpBroadcast` POSTs
to the Realtime REST endpoint (`POST /realtime/v1/api/broadcast`). It does
not open the WebSocket and does not create a `Channel`.

```swift
public extension Realtime {
  /// Single-message shorthand.
  func httpBroadcast<T: Encodable & Sendable>(
    topic: String, event: String, payload: T,
    isPrivate: Bool = false
  ) async throws(RealtimeError)

  /// Batch form.
  func httpBroadcast(_ messages: [HttpBroadcastMessage]) async throws(RealtimeError)
}

public struct HttpBroadcastMessage: Sendable {
  public let topic: String
  public let event: String
  public let payload: any Encodable & Sendable
  public let isPrivate: Bool
}
```

Auth uses the same `APIKeySource` as the WebSocket. Errors use the shared
taxonomy (`.authenticationFailed`, `.rateLimited`, `.serverError`).

---

## 4. Presence

Presence — like broadcast consumption — is gated behind `ChannelSubscription`.
The presence key is still configured at channel creation via `ChannelOptions`
(§2.2); `track`, `observe`, and `diffs` require a live subscription.

```swift
public extension ChannelSubscription {
  var presence: Presence { get }
}

public struct Presence: Sendable {
  /// Begin tracking a state for this client. Multiple concurrent tracks are
  /// supported — each registers a distinct meta under the channel's presence
  /// key (Phoenix multi-meta semantics).
  ///
  /// The handle must be explicitly `cancel()`ed to untrack. Dropping the
  /// handle without cancelling does NOT untrack — but when `channel.leave()`
  /// is called, all outstanding tracks are implicitly torn down server-side.
  ///
  /// Debug warning fires if a handle is deinited without `cancel()` while
  /// the channel is still joined.
  public func track<T: Codable & Sendable>(
    _ state: T
  ) async throws(RealtimeError) -> PresenceHandle

  /// Snapshot + diff stream of all presences, keyed by presence key.
  public func observe<T: Decodable & Sendable>(
    _ type: T.Type
  ) -> AsyncStream<PresenceState<T>>

  /// Incremental diffs only.
  public func diffs<T: Decodable & Sendable>(
    _ type: T.Type
  ) -> AsyncStream<PresenceDiff<T>>
}

public struct PresenceState<T: Sendable>: Sendable {
  public let active: [PresenceKey: [T]]
  public let lastDiff: PresenceDiff<T>?
}

public struct PresenceDiff<T: Sendable>: Sendable {
  public let joined: [(PresenceKey, T)]
  public let left:   [(PresenceKey, T)]
}

public final class PresenceHandle: Sendable {
  /// Idempotent; awaits server ACK of the untrack.
  public func cancel() async throws(RealtimeError)
}
```

- **Presence key source.** Set via `ChannelOptions.presenceKey` at channel
  creation. If `nil`, the server generates a random key per connection —
  Phoenix default behavior.
- **Auto re-track on reconnect.** The SDK remembers the last state passed
  to each live `track()` and re-sends it on rejoin. Presence state is
  restored transparently across transport outages.

---

## 5. Postgres Changes

### 5.1 Declare your table

```swift
@RealtimeTable(schema: "public", table: "messages")
struct Message: Codable, Sendable, Identifiable {
  var id: UUID
  var roomId: UUID
  var text: String
  var createdAt: Date
}
```

`@RealtimeTable` synthesizes:

- Conformance to `RealtimeTable`
- `static let schema: String`, `static let tableName: String`
- A `columnName(for: KeyPath<Self, V>) -> String` lookup, honoring
  `CodingKeys` if the type customizes them

Types the caller doesn't own can conform manually:

```swift
extension ExternalType: RealtimeTable {
  public static let schema = "public"
  public static let tableName = "widgets"
  public static func columnName<V>(for kp: KeyPath<Self, V>) -> String { ... }
}
```

### 5.2 Typed filter — single optional clause

Phoenix Realtime supports exactly one `column=op.value` per postgres_changes
subscription. The SDK reflects this constraint: a single optional `Filter<T>`
per subscription.

```swift
public struct Filter<T: RealtimeTable>: Sendable {
  public static func eq<V: RealtimePostgresFilterValue>(
    _ column: KeyPath<T, V>, _ value: V
  ) -> Filter<T>
  public static func neq<V>(…) -> Filter<T>
  public static func gt<V>(…)  -> Filter<T>
  public static func gte<V>(…) -> Filter<T>
  public static func lt<V>(…)  -> Filter<T>
  public static func lte<V>(…) -> Filter<T>
  public static func `in`<V>(_ column: KeyPath<T, V>, _ values: [V]) -> Filter<T>
}
```

Reads like an enum at call site; implemented as a struct with static
factories so `KeyPath<T, V>` + `V` type binding is preserved. Passing the
wrong value type for a column (`.eq(\.roomId, 42)` when `roomId: UUID`) fails
at compile time.

### 5.3 Register-then-subscribe

Phoenix requires postgres_changes filters in the `phx_join` payload — they
cannot be added after join. The API reflects this: registration mutates
channel state and returns a token; `subscribe()` triggers the join with all
pending tokens; consumption happens through the returned `ChannelSubscription`.

```swift
public extension Channel {
  // Variant-typed factories — token preserves event variant in its type.
  func changes<T: RealtimeTable>(
    to type: T.Type, where filter: Filter<T>? = nil
  ) -> ChangeRegistration<T, AnyEvent>

  func inserts<T: RealtimeTable>(
    into type: T.Type, where filter: Filter<T>? = nil
  ) -> ChangeRegistration<T, Insert>

  func updates<T: RealtimeTable>(
    of type: T.Type, where filter: Filter<T>? = nil
  ) -> ChangeRegistration<T, Update>

  func deletes<T: RealtimeTable>(
    from type: T.Type, where filter: Filter<T>? = nil
  ) -> ChangeRegistration<T, Delete>
}

public struct ChangeRegistration<T, E: ChangeEventVariant>: Sendable {
  // Opaque. Holds enough state for the channel to compose the join payload
  // and route incoming events to consumers.
}

public enum AnyEvent: ChangeEventVariant { public typealias Element = PostgresChange<T> }
public enum Insert:   ChangeEventVariant { public typealias Element = T }
public enum Update:   ChangeEventVariant { public typealias Element = (old: T, new: T) }
public enum Delete:   ChangeEventVariant { public typealias Element = T }

public enum PostgresChange<T: Sendable>: Sendable {
  case insert(T)
  case update(old: T, new: T)
  case delete(T)
}
```

Usage:

```swift
// 1. Register tokens (no join yet).
let inserts  = channel.inserts(into: Message.self, where: .eq(\.roomId, id))
let allMsgs  = channel.changes(to: Message.self,   where: .eq(\.roomId, id))
let roomGone = channel.deletes(from: Room.self,    where: .eq(\.id, id))

// 2. Trigger join. All three tokens land in the same phx_join payload.
let sub = try await channel.subscribe()

// 3. Consume — element type follows the token's variant.
await withThrowingDiscardingTaskGroup { group in
  group.addTask {
    for try await row in sub.events(for: inserts) {
      // row: Message
    }
  }
  group.addTask {
    for try await event in sub.events(for: allMsgs) {
      // event: PostgresChange<Message>
      switch event {
      case .insert(let row):         handle(row)
      case .update(let old, let new): diff(old, new)
      case .delete(let row):         remove(row)
      }
    }
  }
  group.addTask {
    for try await _ in sub.events(for: roomGone) { close() }
  }
}
```

**Tokens are reusable across subscribe cycles.** After `sub.leave()`, the
same tokens replay on the next `channel.subscribe()`. New tokens may also be
registered between leave and resubscribe. Registering while joined throws
`.cannotRegisterAfterJoin`.

**Fan-out per token.** Each `sub.events(for: token)` call returns a fresh
stream; multiple iterators of the same token each receive every event.

**Reconnect is transparent.** `ChannelSubscription` survives silent reconnects
(§9.2); all tokens are re-registered automatically on rejoin. The subscription
is invalidated only by explicit `leave()` or terminal `.transportFailure`.

**AND composition is not available on the wire.** Callers needing multiple
clauses on the same event stream must client-side filter after receipt, or
register two tokens — each produces an independent server subscription
(events may duplicate across the two if the filters overlap, since the
server OR-s them).

### 5.4 Untyped escape hatch

For types without `@RealtimeTable`, the same register-then-subscribe flow
applies — only the filter and element types change.

```swift
let token = channel.changes(
  schema: "public", table: "messages", event: .delete,
  filter: .eq("room_id", id)   // UntypedFilter — string column + any value
)
// token: ChangeRegistration<JSONValue, Delete>

let sub = try await channel.subscribe()

for try await record in sub.events(for: token) {
  // record: JSONValue — caller decodes manually
}
```

---

## 6. Connection

### 6.1 Lazy open

The WebSocket opens lazily on the first `channel.subscribe()` call. There is
no iteration-driven lazy-join in v3 — the only path from "no socket" to
"joined channel" is an explicit `subscribe()`. `httpBroadcast` does not open
the socket.

Explicit `realtime.connect()` is available for callers who want to pre-warm
or surface auth errors early without joining a channel. Calls are idempotent
— a second `connect()` on an already-connected client returns immediately.

### 6.2 Disconnect

```swift
public extension Realtime {
  /// Closes the socket, awaits close ACK. Does NOT evict the channel cache
  /// or call leave() on any channel. Streams throw
  /// `.channelClosed(.transportFailure)`; subsequent operations trigger a
  /// fresh connect + rejoin.
  func disconnect() async
}
```

After a manual `disconnect()`, the `ReconnectionPolicy` does NOT auto-reopen.
The next channel operation (subscribe, send, or explicit `connect()`)
triggers a fresh connect.

### 6.3 Mid-session token rotation

```swift
public extension Realtime {
  /// Push a new token to the server via the Phoenix access_token event.
  /// Keeps private channels authorized without rejoining.
  func updateToken(_ newToken: String) async throws(RealtimeError)
}
```

**Reactive path.** If the server rejects an operation with `token_expired`,
the SDK calls `APIKeySource.dynamic()` once and retries. If the same token
comes back, it propagates `.authenticationFailed`.

**If `dynamic()` throws:** propagates as `.authenticationFailed(underlying:)`.
Connection enters `.closed(.unauthorized)`. The `ReconnectionPolicy` does
NOT apply — auth recovery is caller-owned.

**On `connect()`:** blocks on the first `dynamic()` call. Fail-fast if auth
is broken.

### 6.4 Status

```swift
public extension Realtime {
  var status: AsyncStream<ConnectionStatus> { get }
}

public struct ConnectionStatus: Sendable {
  public enum State: Sendable {
    case idle
    case connecting(attempt: Int)
    case connected
    case reconnecting(attempt: Int, lastError: (any Error & Sendable)?)
    case closed(CloseReason)
  }
  public let state: State
  public let since: Date
  public let latency: Duration?   // last heartbeat RTT
}
```

---

## 7. Error Model

```swift
public enum RealtimeError: Error, Sendable {
  case disconnected
  case transportFailure(underlying: any Error & Sendable)
  case reconnectionGaveUp(lastError: any Error & Sendable)

  case channelJoinTimeout
  case channelJoinRejected(reason: String)
  case channelClosed(CloseReason)
  case cannotRegisterAfterJoin   // postgres_changes registration after join (§5.3)

  case authenticationFailed(reason: String, underlying: (any Error & Sendable)?)
  case tokenExpired

  case rateLimited(retryAfter: Duration?)
  case serverError(code: Int, message: String)

  case broadcastFailed(reason: String)
  case broadcastAckTimeout

  case decoding(type: String, underlying: any Error & Sendable)
  case encoding(underlying: any Error & Sendable)

  case cancelled   // includes task cancellation; Swift's CancellationError is folded here
}
```

Single flat enum. Swift's `CancellationError` is caught internally and
re-thrown as `.cancelled` so call sites exhaustively handle one type.
Underlying errors are preserved as `any Error & Sendable` for debugging.

---

## 8. Transport and Testing

### 8.1 Public transport protocol

```swift
public protocol RealtimeTransport: Sendable {
  func connect(to url: URL, headers: HTTPFields)
    async throws -> any RealtimeConnection
}

public protocol RealtimeConnection: Sendable {
  var frames: AsyncThrowingStream<TransportFrame, any Error & Sendable> { get }
  func send(_ frame: TransportFrame) async throws
  func close(code: Int, reason: String) async
}

public enum TransportFrame: Sendable {
  case text(String)
  case binary(Data)
}
```

### 8.2 Built-in implementations

- `URLSessionTransport` (default). Production. Accepts a custom
  `URLSession` via init for proxy / header / session-config customization.
- `InMemoryTransport.pair()` — test helper in `RealtimeTestHelpers` module.
  Returns `(client, server)`; the server has `send(_:)` and
  `AsyncStream<TransportFrame>` of frames the client sent. Zero real I/O.

### 8.3 Deterministic clock

`Configuration.clock: any Clock<Duration>` lets tests use `TestClock` to
advance heartbeats/timeouts synchronously. Matches existing `swift-clocks`
patterns in the codebase.

---

## 9. Resilience

### 9.1 Reconnection policies

```swift
public struct ReconnectionPolicy: Sendable {
  public var nextDelay: @Sendable (
    _ attempt: Int,
    _ lastError: any Error & Sendable
  ) -> Duration?   // nil = give up

  public static let never: Self
  public static func exponentialBackoff(
    initial: Duration, max: Duration, jitter: Double = 0.2
  ) -> Self
  public static func fixed(_ delay: Duration, maxAttempts: Int?) -> Self
}
```

### 9.2 Behavior during reconnection

- **Streams stay open silently.** No sentinel values — events just pause
  and resume. `channel.state` is the source of truth for lifecycle.
- **Presence is auto-restored.** The SDK re-sends every live `track()`
  state on rejoin. Observers see the re-synced state naturally.
- **Postgres change subscriptions are restored.** Filters re-register on
  join.
- **In-flight sends throw immediately.** `try await channel.broadcast(...)`
  during an outage throws `.disconnected` — no queuing.
- **On give-up.** Channel streams throw `.channelClosed(.transportFailure)`,
  the channel cache evicts affected entries, `channel.state` transitions
  to `.closed(.transportFailure)`. This is distinct from user `leave()` —
  `.transportFailure` means "server-initiated close the SDK surfaces," not
  "you were supposed to call leave."

### 9.3 App lifecycle

```swift
public enum LifecyclePolicy: Sendable {
  case manual
  case automatic
}
```

On `automatic` (default on iOS/macOS/tvOS/visionOS), short
background/foreground cycles keep the socket alive; longer cycles or
OS-killed sockets trigger a reconnect on foreground. No caller code.

---

## 10. Observability

```swift
public protocol RealtimeLogger: Sendable {
  func log(_ event: LogEvent)
}

public struct LogEvent: Sendable {
  public let level: LogLevel          // .debug, .info, .warn, .error
  public let category: Category       // .connection, .channel, .broadcast, .presence, .postgres
  public let message: String
  public let metadata: [String: String]
  public let timestamp: Date
}

public enum LogLevel: Sendable { case debug, info, warn, error }
public enum Category: Sendable { case connection, channel, broadcast, presence, postgres }
```

Ship `OSLogLogger` and `StdoutLogger`. Metrics are logs with numeric
metadata (`heartbeat.rtt_ms`, `reconnect.attempt`, `broadcast.ack_latency_ms`) —
consumers extract as they need via their logger of choice. No swift-metrics
dependency in the core module.

---

## 11. Migration Sketch (V2 → V3)

| V2                                              | V3                                                        |
| ----------------------------------------------- | --------------------------------------------------------- |
| `RealtimeClientV2(url:options:)`                | `Realtime(url:apiKey:configuration:transport:)`           |
| `client.channel("x")`                           | `realtime.channel("x")` (shared; explicit `leave()`)      |
| `await channel.subscribe()`                     | `let sub = try await channel.subscribe()` (returns `ChannelSubscription`) |
| `await channel.unsubscribe()`                   | `try await sub.leave()` (typed throws, global)            |
| `channel.broadcastStream(event:)`               | `sub.broadcasts(of: T.self, event:)` (typed stream)       |
| `await channel.broadcast(event:message:)`       | `try await sub.broadcast(payload, as: event)`             |
| — (no equivalent)                               | `realtime.httpBroadcast(topic:event:payload:)`            |
| `channel.postgresChange(.all, …)`               | `let token = channel.changes(to: Message.self, …); let sub = try await channel.subscribe(); sub.events(for: token)` |
| `channel.presenceChange()`                      | `sub.presence.diffs(T.self)` / `.observe(T.self)`         |
| `channel.track(...)`                            | `try await sub.presence.track(state)` → handle            |
| `ObservationToken` / `subscription.cancel()`    | `AsyncSequence` iteration ends on task cancel             |
| `accessToken: () async -> String?` closure      | `APIKeySource.dynamic(…)` + `realtime.updateToken(…)`     |
| `any Error`                                     | `RealtimeError` (typed throws everywhere)                 |
| `RealtimeClientOptions.maxRetryAttempts` etc.   | `Configuration.reconnection: ReconnectionPolicy`          |
| `options.vsn`                                   | `Configuration.protocolVersion` (default `.v2`)           |
| `options.handleAppLifecycle`                    | unchanged                                                 |

---

## 12. Locked Decisions

Everything below was resolved during design review. Kept here for reference
so implementors don't re-litigate.

| # | Decision | Rationale |
| - | -------- | --------- |
| 1 | Channels are shared by topic within a `Realtime` instance | One server-side subscription per topic; predictable identity |
| 2 | No auto-unsubscribe on `deinit`; explicit `leave()` only | Explicit lifecycle; no ref-count magic |
| 3 | Global `leave()` — other holders' streams throw `.channelClosed(.userRequested)` | Mirrors the wire; surfaces the shared nature |
| 4 | `leave()` is `async throws`, awaits server ACK | Deterministic; consistent with the rest of the API |
| 5 | Pipelined re-acquire after `leave()` | Same-topic churn is transparent |
| 6 | Reconnect is silent in typed streams; `channel.state` is the lifecycle source of truth | Avoids leaky delivery-guarantee abstractions |
| 7 | Unbounded per-subscription buffer (for now) | Simplest; `SlowConsumerPolicy` knob can be added additively |
| 8 | Fan-out: each `broadcasts(of:event:)` call is independent | Matches pub/sub intuition; slow consumer is local |
| 9 | `APIKeySource.dynamic(_:)` for fetch; `updateToken(_:)` for push | No JWT parsing in the SDK |
| 10 | On `token_expired`: retry once, then propagate | Tolerates race between rotation and notify |
| 11 | `dynamic()` throwing does NOT trigger `ReconnectionPolicy` | Auth recovery is caller-owned |
| 12 | Single optional `Filter<T>` per postgres_changes subscription | Reflects the Phoenix wire constraint |
| 13 | `Filter<T>` is a struct with static factories; reads like an enum | Preserves `KeyPath<T, V>` + `V` binding in generics |
| 14 | `@RealtimeTable` macro for column-name resolution; manual conformance as escape hatch | Type-safe without forcing macros on every type |
| 14a | Postgres changes are **register-then-subscribe**: `channel.changes(...)` returns a `ChangeRegistration<T, E>` token; `channel.subscribe()` triggers the join with all pending tokens; consumption via `sub.events(for: token)` | Phoenix requires postgres_changes filters in the join payload — the API can't pretend lazy join works for them |
| 14b | Tokens carry the event variant in their type (`Insert`/`Update`/`Delete`/`AnyEvent`); element type follows the variant | Compiler enforces the right consumer shape per token kind |
| 14c | Registering after join throws `.cannotRegisterAfterJoin`; tokens are reusable across `leave()` + resubscribe cycles | Honest about the wire; ergonomic across reconnects and cycles |
| 14d | `subscribe()` is the **only** join path; no iteration-driven lazy-join | One mental model; no surprises from broadcast iteration silently joining |
| 14e | `subscribe()` returns `ChannelSubscription` — the post-join surface for consumption, sending, and presence | Type-level gate: ops requiring "joined" can only be reached from a `ChannelSubscription` value |
| 14f | `ChannelSubscription` conforms to `AsyncSequence` with `Element = PhoenixMessage` | Untyped raw feed available without an extra method; typed methods refine for normal use |
| 14g | `Channel.broadcast(_:as:)` (sending) is removed; sending lives only on `ChannelSubscription` | Compile-time gate replaces the v3-draft `.channelNotJoined` runtime error |
| 14h | Multiple `subscribe()` calls return equivalent subscriptions sharing one backing state | Topic identity (Decision 1) extends to subscriptions |
| 14i | Subscription drop without `leave()` does nothing (debug warning); leave is global as in Decision 3 | Consistency with channel rules; no auto-leave footguns under topic sharing |
| 14j | `Presence` accessor moves to `ChannelSubscription` (was on `Channel` in earlier draft) | Same gate as broadcast send; track/observe require a live join |
| 14k | `PhoenixMessage` is fully raw — exposes `joinRef`, `ref`, `event`, `payload` (JSON or binary). Includes internal `phx_reply`/`phx_close`/`phx_error` frames | Direct iteration is the escape hatch for advanced consumers; SDK consumes the same frames internally for correlation |
| 14l | `ChannelSubscription.isAlive` / `state` accessor **deferred** | Callers can mirror `realtime.status` or `channel.state`; can be added additively later |
| 15 | `PresenceHandle` is a regular class; explicit `cancel()`; debug warning on leak | Consistent with `Channel` lifecycle rule |
| 16 | Multi-track supported (multiple metas per key) | Matches Phoenix; single-track is the trivial subset |
| 17 | Presence key is channel-level only; server-generated if nil | Simpler; per-track keys confuse more than they help |
| 18 | Auto re-track on reconnect | Presence is a best-effort synced-state abstraction |
| 19 | `withChannel` dropped entirely | Dangerous under global-leave semantics; 3-line explicit pattern is clearer |
| 20 | Flat `RealtimeError` enum; cancellation folded as `.cancelled` | Simpler call sites than grouped or union-throws |
| 21 | Underlying errors preserved as `any Error & Sendable` | Debug value outweighs Equatable/Codable loss |
| 22 | Single `broadcast` method; ack at channel-level config | Uniform call site |
| 23 | Self-broadcast is channel-level only (wire constraint) | Don't lie about the wire |
| 24 | Replay via `ChannelOptions.broadcast.replay` | Config at creation; not a separate method |
| 25 | `Data` payloads bypass encoding; ship as binary frames | Natural Swift affordance |
| 26 | `broadcast` throws `.channelNotJoined` if not joined | Joining is a commitment; one-shot sends go via HTTP |
| 27 | `realtime.httpBroadcast(...)` for one-shot sends; shares `APIKeySource` | Clear separation from WS path |
| 28 | Socket opens lazily on first channel join | Zero ceremony for common paths; explicit `connect()` still exists |
| 29 | `disconnect()` closes socket, keeps channel cache | Pause/resume, not total teardown |
| 30 | `disconnect()` is `async`, awaits close ACK | Consistent with other terminal operations |
| 31 | `connect()` is idempotent | No ceremony for retry paths |
| 32 | No auto-reconnect after manual `disconnect()` | `ReconnectionPolicy` is for unexpected closes |
| 33 | Duplicate `channel(topic)` with different options: first-call wins + debug warning | Silent drift is worse than a warning |
| 34 | `@RealtimeSchema` (typed event channels) deferred | Per-call generics cover 90% of the typing benefit; macro complexity can wait |
| 35 | Public `RealtimeTransport` protocol | Custom transports for testing and advanced networking |
| 36 | Ship `InMemoryTransport.pair()` in test helpers | Table stakes for deterministic testing |
| 37 | Inject `Clock<Duration>` via `Configuration` | Deterministic timeout/heartbeat tests |
| 38 | Drop obsoleted V2 knobs (`connectOnSubscribe`, `maxRetryAttempts`, `logLevel`, `fetch`, `accessToken`, `disconnectOnSessionLoss`) | Subsumed by better abstractions |
| 39 | Keep `disconnectOnEmptyChannelsAfter` (socket idle timeout) and `protocolVersion` | Still useful |
| 40 | Per-operation timeouts: `joinTimeout`, `leaveTimeout`, `broadcastAckTimeout` | One global knob can't tune distinct round-trips |
| 41 | Logger only; no separate metrics stream; no swift-metrics dep | Metrics = logs with numeric metadata |
| 42 | No custom join payload | Unused in practice; removes surface |
| 43 | Multiple `Realtime` instances are fully independent | No singleton; no hidden coupling |
| 44 | Topic strings are not validated | Server is the source of truth for validity |
| 45 | Presence key default: server-generated when nil | Matches Phoenix |

---

## Appendix A — End-to-end example

```swift
import Realtime

@RealtimeTable(schema: "public", table: "messages")
struct Message: Codable, Sendable, Identifiable {
  var id: UUID
  var roomId: UUID
  var text: String
  var authorId: UUID
  var createdAt: Date
}

struct UserPresence: Codable, Sendable {
  let userId: UUID
  let status: Status
  enum Status: String, Codable, Sendable { case active, idle }
}

@MainActor @Observable
final class ChatRoomModel {
  private let realtime: Realtime
  private let channel: Channel
  private let roomId: UUID
  private var runTask: Task<Void, Never>?
  private var subscription: ChannelSubscription?
  private var trackHandle: PresenceHandle?

  var messages: [Message] = []
  var onlineUsers: [UUID: UserPresence] = [:]
  var connection: ConnectionStatus.State = .idle

  init(realtime: Realtime, roomId: UUID) {
    self.realtime = realtime
    self.roomId = roomId
    self.channel = realtime.channel("chat:room:\(roomId)") {
      $0.presenceKey = "user-\(Self.currentUserID)"
    }
  }

  func start(me: UUID) {
    // Register postgres tokens BEFORE subscribe — they bake into phx_join.
    let messageInserts = channel.inserts(
      into: Message.self, where: .eq(\.roomId, roomId)
    )

    runTask = Task { [channel, realtime, messageInserts, weak self] in
      do {
        // Single explicit join captures the registration above.
        let sub = try await channel.subscribe()
        await MainActor.run { self?.subscription = sub }

        try await withThrowingDiscardingTaskGroup { group in
          // Postgres inserts → append
          group.addTask {
            for try await row in sub.events(for: messageInserts) {
              await MainActor.run { self?.messages.append(row) }
            }
          }
          // Presence observers
          group.addTask {
            for await state in sub.presence.observe(UserPresence.self) {
              let mapped = Dictionary(
                uniqueKeysWithValues: state.active.values
                  .flatMap { $0 }
                  .map { ($0.userId, $0) }
              )
              await MainActor.run { self?.onlineUsers = mapped }
            }
          }
          // Track myself
          group.addTask {
            let handle = try await sub.presence.track(
              UserPresence(userId: me, status: .active)
            )
            await MainActor.run { self?.trackHandle = handle }
          }
          // Connection status mirror
          group.addTask {
            for await status in realtime.status {
              await MainActor.run { self?.connection = status.state }
            }
          }
        }
      } catch is CancellationError {
        // expected on view teardown
      } catch let error as RealtimeError {
        print("chat failed:", error)   // exhaustive — compiler enforces
      }
    }
  }

  /// Broadcast through the active subscription. Type-level gate: cannot
  /// be called before `subscription` is set. One server-side subscription;
  /// one round-trip.
  func send(_ text: String, from author: UUID) async throws(RealtimeError) {
    guard let subscription else { return }
    try await subscription.broadcast(
      ChatMessage(authorId: author, text: text),
      as: "chat"
    )
  }

  func stop() async {
    runTask?.cancel()
    try? await trackHandle?.cancel()
    try? await subscription?.leave()
  }
}
```

---

## Appendix B — Why not Combine?

- `AsyncSequence` is the lingua franca of new Apple frameworks.
- Combine cannot express typed throws or structured cancellation cleanly.
- Callers who want Combine can wrap any stream in `Publisher` in ~5 lines —
  the reverse is lossy.

## Appendix C — Platform requirements

- Swift 6.2+ (typed throws, isolated deinit, macros at the required level)
- iOS 17+ / macOS 14+ / tvOS 17+ / watchOS 10+ / visionOS 1+ for
  `@Observable`. A non-Observable compatibility layer could extend support
  to iOS 13+ at the cost of ergonomic integration.
