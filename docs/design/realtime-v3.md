# Realtime v3 — Idiomatic Swift API Proposal

> Status: Design revisited after backend source audit
> (`realtime-v3-questions-for-backend.md`). Greenfield design — no
> consideration given to V2 compatibility or other Supabase SDKs. Targets Swift
> 6.2+. Breaking changes accepted.

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
  apiKey: "anon-key",
  accessToken: { try await auth.session.accessToken }
)

let channel = await realtime.channel("room:42")

// Optional: register postgres tokens BEFORE subscribe.
let inserts = await channel.inserts(into: Message.self, where: .eq(\.roomId, 42))

// Single explicit join.
try await channel.subscribe()

// Typed broadcast receive.
Task {
  let chats = await channel.broadcasts(of: ChatBroadcast.self, event: "chat")
  for try await msg in chats { render(msg) }
}

// Postgres consumption.
Task {
  let rows = await channel.postgresChanges(for: inserts)
  for try await row in rows { append(row) }
}

// Untyped raw feed.
Task {
  for await frame in await channel.messages() {
    // frame: PhoenixMessage — broadcast / postgres_changes / presence_diff / ...
  }
}

// WebSocket send (requires a subscribed channel).
let payload = ChatBroadcast(...)   // any Encodable & Sendable
try await channel.broadcast(payload, as: "chat")

// Explicit release when done.
try await channel.leave()
```

One-shot HTTP send without joining:

```swift
try await channel.httpBroadcast(
  event: "chat",
  payload: ChatBroadcast(...)
)
```

That's the mental model:

- **Channels are topic handles.** `realtime.channel(topic)` returns a handle for
  registering postgres tokens, triggering `subscribe()`, and issuing
  topic-scoped HTTP broadcasts without joining.
- **`subscribe()` joins the channel.** After it returns, the same `Channel`
  handle is used for all consumption (typed and untyped), WebSocket sending,
  presence, and `leave()`. Runtime state determines whether an operation is
  currently allowed.
- **Postgres changes are register-then-subscribe.** The Phoenix wire forces it;
  the API reflects it. Tokens are reusable across `leave()` cycles.
- **One `phx_join` per topic.** All pending tokens land in that single join.

Everything below is elaboration.

---

## 1. Client Construction

```swift
public actor Realtime {
  public init(
    url: URL,
    apiKey: String,
    accessToken: AccessTokenProvider? = nil,
    configuration: Configuration = .default,
    transport: any RealtimeTransport = URLSessionTransport()
  )
}
```

### 1.1 Credentials separate literal API key from dynamic access token

```swift
/// Called before joining private/RLS-backed channels, before HTTP private
/// broadcasts, and during reconnect/resubscribe. This is a JWT access token,
/// not the project API key.
public typealias AccessTokenProvider = @Sendable () async throws -> String
```

The backend uses different credentials in different places:

- WebSocket connect uses the `apikey` query parameter or `x-api-key` header.
  It does not read `Authorization` during the socket handshake.
- Channel joins and token rotation can carry an access token in the join
  payload or `access_token` channel event.
- HTTP broadcast accepts `Authorization: Bearer <jwt>` first, then an
  `apikey` header fallback. It does not use the WebSocket `x-api-key` header.

The SDK keeps those concepts separate. `apiKey` is required for connecting.
It is a literal string because project API keys do not rotate per operation in
the client. `accessToken` is optional for public channels but required for
private channels and RLS-backed operations. It is always dynamic because JWTs
expire and can change with auth session state.

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
  public var lifecycle: LifecyclePolicy = .automaticDefault
  public var protocolVersion: RealtimeProtocolVersion = .v2
  public var clock: any Clock<Duration> & Sendable = ContinuousClock()
  public var headers: HTTPFields = [:]
  public var logger: (any RealtimeLogger)? = nil
  public var decoder: JSONDecoder = .realtimeDefault   // ISO 8601 dates
  public var encoder: JSONEncoder = .realtimeDefault   // ISO 8601 dates

  public static let `default` = Configuration()
}

extension LifecyclePolicy {
  /// `.automatic` on iOS/macOS/tvOS/visionOS; `.manual` elsewhere
  /// (including watchOS and Linux, where lifecycle observation is
  /// not supported).
  public static let automaticDefault: LifecyclePolicy
}

extension JSONDecoder {
  /// SDK-provided decoder configured with `.iso8601` date strategy.
  /// Replace via `Configuration.decoder` for custom needs.
  public static let realtimeDefault: JSONDecoder
}

extension JSONEncoder {
  /// SDK-provided encoder configured with `.iso8601` date strategy.
  public static let realtimeDefault: JSONEncoder
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
  /// The channel does not join the server until `subscribe()` is called. The
  /// caller must call `leave()` to unsubscribe; `deinit` does NOT unsubscribe.
  ///
  /// Isolated: the topic→channel registry is actor state (Decision 1), so
  /// lookup/creation reads-modifies-writes it and callers `await`.
  func channel(
    _ topic: String,
    configure: (inout ChannelOptions) -> Void = { _ in }
  ) -> Channel
}

public actor Channel {
  // Immutable metadata — `nonisolated let` (no `await` to read).
  public nonisolated let topic: String
  public nonisolated let options: ChannelOptions

  /// Lifecycle stream. Isolated — backed by state stored in the actor.
  public var state: AsyncStream<ChannelState> { get }

  /// Explicit join. Idempotent: calling while joined returns immediately;
  /// concurrent calls before join await the same in-flight join.
  ///
  /// Postgres-change registrations made before this call are baked into the
  /// `phx_join` payload (see §5). After the call returns, registration of
  /// new tokens throws `.cannotRegisterAfterJoin` until the next `leave()`.
  public func subscribe() async throws(RealtimeError)

  /// Explicit unsubscribe. Global (§2.3); awaits server channel close
  /// confirmation. After leave, live methods throw `.channelClosed`.
  public func leave() async throws(RealtimeError)

  /// One-shot HTTP broadcast to this channel's topic. Does not join the
  /// channel and does not open the WebSocket.
  public func httpBroadcast<T: Encodable & Sendable>(
    event: String, payload: T,
    isPrivate: Bool = false
  ) async throws(RealtimeError)

  /// Raw feed — every Phoenix frame on this channel, including `broadcast`,
  /// `postgres_changes`, `presence_diff`, `presence_state`, `system`,
  /// `phx_reply`, `phx_close`, and `phx_error`. The SDK still consumes these
  /// internally (ack correlation, lifecycle); raw consumers observe a copy.
  ///
  /// A method, not a property: each call mints a fresh, independent stream
  /// (per-call fan-out). Isolated — it registers a consumer in the actor's
  /// routing state, so callers `await channel.messages()`.
  public func messages() -> AsyncStream<PhoenixMessage>

  // Typed stream factories (§3, §5). Isolated — each registers a consumer in
  // the actor; callers `await` to obtain the stream, then iterate it.
  public func broadcasts<T: Decodable & Sendable>(of type: T.Type, event: String)
    -> AsyncThrowingStream<T, RealtimeError>
  public func postgresChanges<E: ChangeEventVariant>(for token: ChangeRegistration<E>)
    -> AsyncThrowingStream<E.Element, RealtimeError>

  /// Presence namespace. `nonisolated` because it only wraps `self`; its
  /// stream methods register lazily on first iteration (§4).
  public nonisolated var presence: Presence { get }

  // Postgres-change registration (§5.3) is isolated — see that section.

  // Sending (§3.2) — requires a subscribed channel at runtime; isolated.
  public func broadcast<T: Encodable & Sendable>(_ payload: T, as event: String)
    async throws(RealtimeError)
  public func broadcast(_ data: Data, as event: String) async throws(RealtimeError)
}
```

**Isolation contract.** `Channel` is a plain actor that owns all of its state
(join status, the WebSocket, in-flight pushes, stream-routing tables, pending
registrations). There is no separate Sendable side-store — the actor is the
single source of truth.

- `nonisolated` (no `await`): only the immutable constants `topic` and
  `options`, plus the `presence` accessor (which merely wraps `self`; its
  stream methods register lazily on first iteration, §4).
- **isolated** (`await` at the call site): everything that reads or mutates
  actor state — `state`, `messages()`, `broadcasts(of:event:)`,
  `postgresChanges(for:)`, the registration factories
  `changes`/`inserts`/`updates`/`deletes` (§5.3), `subscribe()`, `leave()`,
  `broadcast(_:as:)`, `httpBroadcast(...)`, `presence.track(...)`, and
  `realtime.channel(_:)`. Stream factories register a consumer in the actor
  and return the stream, so obtaining one is `await`; iterating it then
  suspends as values arrive.

Registering tokens before `subscribe()` is therefore `let t = await
channel.inserts(...)` — async, but still before join, and stored in the
actor's pending-registration set.

```swift
public struct PhoenixMessage: Sendable {
  /// Phoenix join reference correlating this frame to its `phx_join`. Always
  /// `nil` when the channel is configured for protocol v1 (4-tuple frames
  /// have no joinRef field). Under v2: `nil` for frames that predate the
  /// current join (rare).
  public let joinRef: String?

  /// Phoenix message reference for request/reply correlation. Set on
  /// pushes the SDK sent and on the matching `phx_reply`. `nil` for
  /// server-pushed events (`broadcast`, `postgres_changes`, etc.).
  public let ref: String?

  /// Channel topic this frame belongs to. Always matches this channel's topic
  /// for channel iterators; included on the struct so consumers that hand
  /// `PhoenixMessage` values across boundaries (logging, debugging,
  /// multi-topic aggregation) keep the routing key.
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
- **No auto-unsubscribe.** Dropping a `Channel` does nothing. Explicit
  `leave()` is the only way.
- **`subscribe()` is the only join path.** No lazy-join via iteration. The
  WebSocket opens lazily on the first `subscribe()` (§6.1).
- **Postgres tokens register before join.** `channel.changes(...)`,
  `channel.inserts(...)`, etc. mutate channel state and return tokens. Calling
  these *after* the channel has joined throws `.cannotRegisterAfterJoin`. After
  `leave()`, registration is allowed again — tokens are reusable across
  subscribe cycles. (§5)
- **Live mutations and sends are runtime-gated.** `broadcast` and
  `presence.track` are methods on `Channel`, but they require the channel to be
  subscribed. Before subscribe they throw `.notSubscribed`; after manual leave
  or terminal close they throw `.channelClosed(...)`. During reconnect, streams
  stay open and sends throw `.disconnected`.
- **`subscribe()` is idempotent.** Multiple callers share the same backing
  channel state. A single `leave()` ends the channel for every holder of the
  topic.
- **Streams belong to the channel.** They can be created before subscribe and
  will start producing only after the channel joins. Manual `leave()` terminates
  streams with `.channelClosed(.userRequested)`. Reconnects do not terminate
  streams unless the reconnection policy gives up.
- **Leaked-channel warning.** When `Realtime` deinits with channels that
  have been joined but never left, an `IssueReporting` warning fires in
  debug builds. Release builds silently rely on server-side timeouts.

### 2.2 Channel options are locked at creation

```swift
public struct ChannelOptions: Sendable {
  public var isPrivate: Bool = false
  public var broadcast: BroadcastOptions = .init()
  public var presence: PresenceOptions = .init()
}

public struct BroadcastOptions: Sendable {
  public var acknowledge: Bool = false
  public var receiveOwnBroadcasts: Bool = false
  /// Backend replay is join-time-only and private-channel-only.
  public var replay: ReplayOption? = nil
}

public struct ReplayOption: Sendable {
  public var since: Date
  public var limit: Int?
}

public struct PresenceOptions: Sendable {
  /// Sends `presence.enabled = true` in the join config. Required for an
  /// initial `presence_state` snapshot on join. If false, `track` can still
  /// create/update presence later, but observers cannot retroactively get the
  /// initial snapshot.
  public var enabled: Bool = false

  /// Presence key for this channel process. If nil/empty, the server generates
  /// a fresh UUID per join.
  public var key: String? = nil
}
```

Options are applied on the first `channel(topic)` call. **A later call with a
different `configure` closure is ignored** — the first call wins. An
`IssueReporting` warning fires in debug. The returned `Channel.options`
reflects the effective options.

`BroadcastOptions.replay` is valid only with `isPrivate == true`; public-channel
replay is rejected by the backend. Replay `limit` is clamped server-side to
1...25, defaulting to 25 when omitted.

`PresenceOptions.enabled` should be set when the caller intends to observe
presence state. Setting `PresenceOptions.key` does not by itself create
presence; it only controls the key used when this channel tracks.

### 2.3 `leave()` semantics (shared-handle model)

- `leave()` is **global**: it tears down the subscription for every holder of
  the same topic. Other holders' active streams terminate by throwing
  `RealtimeError.channelClosed(.userRequested)`.
- `leave()` is **await-to-close**: it returns only after the server confirms
  channel close (`phx_close` / Phoenix leave completion). On transport failure
  or timeout, it throws.
- A **pipelined re-acquire** is safe: if `realtime.channel("x")` is called
  while a leave for `"x"` is in flight, the caller gets the same `Channel`
  actor (topic identity, Decision 1) — now in `unsubscribed` state — and the
  next `subscribe()` is queued behind the pending leave. Same-topic churn is
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
  case clientDisconnected     // someone called realtime.disconnect()
  case serverClosed(code: Int?, message: String?)
  case timeout
  case unauthorized
  case policyViolation(String)
  case transportFailure       // reconnection policy gave up
}
```

The backend does not expose a stable custom WebSocket close-code taxonomy for
auth, rate limit, and policy failures. `code` is optional because many terminal
channel states arrive as `system` + `phx_close` rather than a meaningful
transport close code.

---

## 3. Broadcast

All broadcast surfaces — typed receiving, typed WebSocket sending, HTTP
one-shot sending, and the untyped iteration over the raw Phoenix feed — live on
`Channel`. WebSocket sending requires the channel to be subscribed at runtime.

### 3.1 Receiving

```swift
public extension Channel {
  /// Typed event stream — decodes each broadcast message's payload to `T`,
  /// filtered to a single event name. Fan-out is **per call**: each call
  /// returns an independent stream, and N calls observe every matching
  /// message N times. A single returned stream still follows
  /// `AsyncThrowingStream` semantics — one consumer per value; iterating the
  /// same returned stream from two tasks splits values between them. For two
  /// consumers, call `broadcasts(of:event:)` twice.
  ///
  /// Isolated: `await channel.broadcasts(...)` to obtain the stream.
  func broadcasts<T: Decodable & Sendable>(
    of type: T.Type,
    event: String
  ) -> AsyncThrowingStream<T, RealtimeError>
}

// Untyped iteration is the `channel.messages()` stream (§2.1). Element is
// `PhoenixMessage`, which spans broadcasts, postgres_changes, presence_diff,
// and other channel-level events. To filter to broadcasts only, match on
// `event == "broadcast"` and decode `payload` manually — but the typed
// `broadcasts(of:event:)` method is the recommended path.
```

Streams pause silently during reconnection and resume on rejoin. Gaps are
inherent in fire-and-forget pub/sub and not surfaced — callers who care
correlate against `channel.state`.

Backpressure: each stream has an **unbounded** buffer. A slow consumer
will accumulate pending messages and eventually OOM under sustained lag. A
`SlowConsumerPolicy` knob may be added later without breaking source. The
backend does not provide a durable per-subscriber queue or a client-visible
backpressure contract.

### 3.2 Sending

```swift
public extension Channel {
  /// Sends a broadcast. Behavior depends on `ChannelOptions.broadcast.acknowledge`:
  /// - `false` (default): fire-and-forget; returns after the frame is queued.
  /// - `true`: awaits server ack; throws on timeout (`broadcastAckTimeout`).
  ///   The backend can silently drop unauthorized private-channel broadcasts,
  ///   so timeout is also the observable failure mode for that edge.
  ///
  /// Throws `.notSubscribed` before the channel has joined. Throws
  /// `.channelClosed` if `leave()` has been called or the channel terminally
  /// closed. Throws `.disconnected` if the socket is down — no queuing.
  func broadcast<T: Encodable & Sendable>(
    _ payload: T,
    as event: String
  ) async throws(RealtimeError)

  /// `Data` bypasses encoding and ships as a binary frame (Phoenix v2).
  /// The backend accepts arbitrary bytes subject to tenant payload limits and
  /// the WebSocket max frame size.
  func broadcast(_ data: Data, as event: String) async throws(RealtimeError)
}
```

WebSocket sends are not queued across disconnected periods. A send before
`subscribe()` fails with `.notSubscribed`; a send during reconnect fails with
`.disconnected`; a send after leave fails with `.channelClosed(...)`.

### 3.3 HTTP one-shot broadcast

For senders that don't need to join, `channel.httpBroadcast` POSTs to
the Realtime HTTP broadcast endpoint for that channel's topic. It does not open
the WebSocket and does not join the channel.

```swift
public extension Channel {
  /// Single-message HTTP broadcast. Uses
  /// `POST /realtime/v1/api/broadcast/:topic/events/:event`.
  func httpBroadcast<T: Encodable & Sendable>(
    event: String, payload: T,
    isPrivate: Bool = false
  ) async throws(RealtimeError)
}

public extension Realtime {
  /// Multi-topic batch form. Uses `POST /realtime/v1/api/broadcast` with
  /// `{ "messages": [...] }`. This remains on `Realtime` because a batch can
  /// contain messages for multiple topics.
  func httpBroadcastBatch(_ messages: [HttpBroadcastMessage]) async throws(RealtimeError)
}

public struct HttpBroadcastMessage: Sendable {
  public let topic: String
  public let event: String
  public let payload: any Encodable & Sendable
  public let isPrivate: Bool
}
```

HTTP broadcast auth uses `Authorization: Bearer <accessToken>` when an
`accessToken` provider is configured and falls back to the `apikey` header. This is
deliberately different from the WebSocket connect path, which uses `apikey` or
`x-api-key`.

Success is `202 Accepted` with no response body. Errors map into the shared
taxonomy where the backend provides enough information
(`.authenticationFailed`, `.rateLimited`, `.serverError`). HTTP rate-limit
responses expose `x-rate-*` headers but no `Retry-After`, so
`.rateLimited(retryAfter:)` is normally `nil`.

Batch and single-message private broadcasts have different backend failure
semantics: `channel.httpBroadcast` private unauthorized returns forbidden; batch
private unauthorized messages can be skipped while the request still returns
`202` for the accepted work. The SDK documents this instead of pretending batch
is a transaction.

---

## 4. Presence

Presence lives on `Channel`. Join-time presence behavior is configured through
`ChannelOptions.presence` (§2.2); `track` requires a subscribed channel at
runtime, while observation streams may be created before subscribe and start
emitting after join.

```swift
public extension Channel {
  nonisolated var presence: Presence { get }
}

public struct Presence: Sendable {
  /// Begin tracking, or update the existing tracked state, for this
  /// channel process. The backend stores one meta per channel process and presence
  /// key; repeated calls update that meta rather than registering additional
  /// metas.
  ///
  /// The returned handle represents that single presence slot. Calling
  /// `track` again while the handle is live is equivalent to
  /// `handle.update(newState)` and returns a handle for the same logical slot.
  /// The handle must be explicitly `cancel()`ed to untrack. Dropping the
  /// handle without cancelling does NOT untrack — but when `leave()` is called
  /// on any holder of the topic, the slot is implicitly torn down server-side.
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

/// The presence key string the server attaches to each meta. Comes from
/// `ChannelOptions.presence.key` if set, otherwise server-generated.
public typealias PresenceKey = String

public struct PresenceState<T: Sendable>: Sendable {
  public let active: [PresenceKey: [T]]
  public let lastDiff: PresenceDiff<T>?
}

public struct PresenceDiff<T: Sendable>: Sendable {
  public let joined: [(PresenceKey, T)]
  public let left:   [(PresenceKey, T)]
}

public final class PresenceHandle: Sendable {
  /// Update the current presence meta. This does not create a second meta.
  public func update<T: Codable & Sendable>(_ state: T) async throws(RealtimeError)

  /// Idempotent; awaits server ACK of the untrack.
  public func cancel() async throws(RealtimeError)
}
```

- **Presence key source.** Set via `ChannelOptions.presence.key` at channel
  creation. If `nil` or empty, the server generates a fresh UUID per join.
- **Presence snapshots.** `presence_state` is sent on join only when
  `ChannelOptions.presence.enabled` is true. `track` can still create/update
  presence later, but it cannot retroactively request the initial snapshot.
- **Auto re-track on reconnect.** The SDK remembers the last state passed
  to the live presence slot and re-sends it on rejoin. Presence state is
  restored transparently across transport outages, but only the latest state is
  restored because the backend has one meta per channel process/key.

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

### 5.2 Filters — typed and untyped

Phoenix Realtime supports one filter string per `postgres_changes` entry, but
that string can contain multiple comma-separated clauses. Clauses are ANDed by
the backend. The SDK reflects this with composable filter values. OR is modeled
by registering multiple tokens and routing the backend `ids` array to each
matching registration.

Two filter types use the same wire encoding but different input shapes:

```swift
/// Type-checked filter for `RealtimeTable` types. Column is a `KeyPath`; the
/// value's type must match the keypath's `Value`. `.eq(\.roomId, 42)` against
/// `var roomId: UUID` fails at compile time.
public struct Filter<T: RealtimeTable>: Sendable {
  public static func eq<V: RealtimePostgresFilterValue>(
    _ column: KeyPath<T, V>, _ value: V
  ) -> Filter<T>
  public static func neq<V>(…) -> Filter<T>
  public static func gt<V>(…)  -> Filter<T>
  public static func gte<V>(…) -> Filter<T>
  public static func lt<V>(…)  -> Filter<T>
  public static func lte<V>(…) -> Filter<T>
  public static func `in`<V: RealtimePostgresFilterValue>(
    _ column: KeyPath<T, V>, _ values: [V]
  ) -> Filter<T>
  public static func like(_ column: KeyPath<T, String>, _ pattern: String) -> Filter<T>
  public static func ilike(_ column: KeyPath<T, String>, _ pattern: String) -> Filter<T>
  public static func match(_ column: KeyPath<T, String>, _ pattern: String) -> Filter<T>
  public static func imatch(_ column: KeyPath<T, String>, _ pattern: String) -> Filter<T>
  public static func isNull<V>(_ column: KeyPath<T, V?>) -> Filter<T>
  public static func isNotNull<V>(_ column: KeyPath<T, V?>) -> Filter<T>
  public static func isDistinct<V: RealtimePostgresFilterValue>(
    _ column: KeyPath<T, V>, _ value: V
  ) -> Filter<T>

  public func and(_ other: Filter<T>) -> Filter<T>
  public static func all(_ filters: [Filter<T>]) -> Filter<T>
  public static func not(_ filter: Filter<T>) -> Filter<T>
}

/// Untyped filter for cases where the row type cannot or does not conform
/// to `RealtimeTable`. Column is a raw string; values are still constrained
/// to `RealtimePostgresFilterValue` for correct wire encoding.
public struct UntypedFilter: Sendable {
  public static func eq(_ column: String,
                         _ value: any RealtimePostgresFilterValue) -> UntypedFilter
  public static func neq(…) -> UntypedFilter
  public static func gt(…)  -> UntypedFilter
  public static func gte(…) -> UntypedFilter
  public static func lt(…)  -> UntypedFilter
  public static func lte(…) -> UntypedFilter
  public static func `in`(_ column: String,
                           _ values: [any RealtimePostgresFilterValue]) -> UntypedFilter
  public static func like(_ column: String, _ pattern: String) -> UntypedFilter
  public static func ilike(_ column: String, _ pattern: String) -> UntypedFilter
  public static func match(_ column: String, _ pattern: String) -> UntypedFilter
  public static func imatch(_ column: String, _ pattern: String) -> UntypedFilter
  public static func isNull(_ column: String) -> UntypedFilter
  public static func isNotNull(_ column: String) -> UntypedFilter
  public static func isDistinct(
    _ column: String, _ value: any RealtimePostgresFilterValue
  ) -> UntypedFilter

  public func and(_ other: UntypedFilter) -> UntypedFilter
  public static func all(_ filters: [UntypedFilter]) -> UntypedFilter
  public static func not(_ filter: UntypedFilter) -> UntypedFilter
}
```

Each clause serializes to `column=op.value`; a compound filter serializes as
`clause,clause`. The split is purely about call-site ergonomics — typed gets
compile-time checking via `KeyPath`, untyped pays runtime cost for not requiring
conformance.

`in` values are encoded with backend-compatible quoting/escaping and must not
exceed 100 values. `not` maps to the backend `not.` prefix and applies to each
clause in the filter it wraps. `is` supports null checks through
`isNull`/`isNotNull`; boolean/unknown helpers can be added if use cases need
them.

### 5.3 Register-then-subscribe

Phoenix requires postgres_changes filters in the `phx_join` payload — they
cannot be added after join. The API reflects this: registration records the
token in the actor's pending-registration set; `subscribe()` triggers the join
with all pending tokens; consumption happens through the same `Channel`.

```swift
public extension Channel {
  // All registration factories are isolated (they mutate the actor's
  // pending-registration set), so callers `await` them — still before
  // `subscribe()`. See §2.1 "Isolation contract".

  // Typed factories — require RealtimeTable, return registrations whose
  // variant carries the row type. Filter is a typed `Filter<T>`.
  func changes<T: RealtimeTable>(
    to type: T.Type, where filter: Filter<T>? = nil
  ) -> ChangeRegistration<AnyEvent<T>>

  func inserts<T: RealtimeTable>(
    into type: T.Type, where filter: Filter<T>? = nil
  ) -> ChangeRegistration<Insert<T>>

  func updates<T: RealtimeTable>(
    of type: T.Type, where filter: Filter<T>? = nil
  ) -> ChangeRegistration<Update<T>>

  func deletes<T: RealtimeTable>(
    from type: T.Type, where filter: Filter<T>? = nil
  ) -> ChangeRegistration<Delete<T>>

  // Untyped factories — for types without RealtimeTable. Return registrations
  // whose variant carries `JSONValue`. Filter is `UntypedFilter`.
  func changes(
    schema: String, table: String, filter: UntypedFilter? = nil
  ) -> ChangeRegistration<AnyEvent<JSONValue>>

  func inserts(
    schema: String, table: String, filter: UntypedFilter? = nil
  ) -> ChangeRegistration<Insert<JSONValue>>

  func updates(
    schema: String, table: String, filter: UntypedFilter? = nil
  ) -> ChangeRegistration<Update<JSONValue>>

  func deletes(
    schema: String, table: String, filter: UntypedFilter? = nil
  ) -> ChangeRegistration<Delete<JSONValue>>
}

/// Variant protocol — each variant is itself generic over the row type and
/// declares the element type of `postgresChanges(for:)` for that variant.
public protocol ChangeEventVariant: Sendable {
  associatedtype Element: Sendable
}

public enum Insert<T: Sendable>:   ChangeEventVariant { public typealias Element = T }
public enum Update<T: Sendable>:   ChangeEventVariant { public typealias Element = PostgresUpdate<T> }
public enum Delete<T: Sendable>:   ChangeEventVariant { public typealias Element = PostgresDelete<T> }
public enum AnyEvent<T: Sendable>: ChangeEventVariant { public typealias Element = PostgresChange<T> }

public struct PostgresUpdate<T: Sendable>: Sendable {
  /// Fully decoded new row (`record`).
  public let record: T

  /// Raw `old_record`. The backend does not guarantee this is a full row;
  /// without `REPLICA IDENTITY FULL`, or under RLS, it may contain only key
  /// columns.
  public let oldRecord: JSONValue?
}

public struct PostgresDelete<T: Sendable>: Sendable {
  /// Raw `old_record`. This is not guaranteed to decode as `T` unless the
  /// table and RLS configuration make the full old row available.
  public let oldRecord: JSONValue
}

/// Single generic over the variant — variant carries `T`, no extra type
/// parameter on the registration. Same registration type for typed and
/// untyped paths; only the variant's `T` differs.
public struct ChangeRegistration<E: ChangeEventVariant>: Sendable {
  // Opaque. Holds the table descriptor (typed via RealtimeTable, or raw
  // schema+table strings), optional filter, event mask, and routing state.
}

public extension Channel {
  /// Single overload, dispatched on the variant. Element type follows from
  /// `E.Element` — `T` for inserts, `PostgresUpdate<T>` for updates,
  /// `PostgresDelete<T>` for deletes, `PostgresChange<T>` for `AnyEvent`.
  /// Works identically for typed and untyped registrations (`T` is `JSONValue`
  /// in the untyped case).
  ///
  /// Passing a token that was created on a different channel is a
  /// programmer error: the iterator throws `.unknownToken` on first
  /// iteration. (`Channel` actor identity is captured in the token.)
  ///
  /// Isolated: `await channel.postgresChanges(for:)` to obtain the stream.
  func postgresChanges<E: ChangeEventVariant>(for token: ChangeRegistration<E>)
    -> AsyncThrowingStream<E.Element, RealtimeError>
}

public enum PostgresChange<T: Sendable>: Sendable {
  case insert(T)
  case update(PostgresUpdate<T>)
  case delete(PostgresDelete<T>)
}
```

Usage:

```swift
// 1. Register tokens (no join yet) — async, but still before subscribe.
let inserts  = await channel.inserts(into: Message.self, where: .eq(\.roomId, id))
let allMsgs  = await channel.changes(to: Message.self,   where: .eq(\.roomId, id))
let roomGone = await channel.deletes(from: Room.self,    where: .eq(\.id, id))

// 2. Trigger join. All three tokens land in the same phx_join payload.
try await channel.subscribe()

// 3. Consume — element type follows the token's variant.
await withThrowingDiscardingTaskGroup { group in
  group.addTask {
    for try await row in await channel.postgresChanges(for: inserts) {
      // row: Message
    }
  }
  group.addTask {
    for try await event in await channel.postgresChanges(for: allMsgs) {
      // event: PostgresChange<Message>
      switch event {
      case .insert(let row):         handle(row)
      case .update(let change):      render(change.record, previous: change.oldRecord)
      case .delete(let change):      remove(usingOldRecord: change.oldRecord)
      }
    }
  }
  group.addTask {
    for try await _ in await channel.postgresChanges(for: roomGone) { close() }
  }
}
```

**Tokens are reusable across subscribe cycles.** After `channel.leave()`, the
same tokens replay on the next `channel.subscribe()`. New tokens may also be
registered between leave and resubscribe. Registering while joined throws
`.cannotRegisterAfterJoin`.

**Fan-out per token.** Fan-out is **per call**: each
`channel.postgresChanges(for: token)` call returns a fresh stream, and N calls
each receive every event. A single returned stream is single-consumer
(standard `AsyncThrowingStream` semantics) — for two consumers of the same
token, call `postgresChanges(for:)` twice rather than iterating one returned
stream from two tasks.

**Reconnect is transparent.** Channel streams survive silent reconnects (§9.2);
all tokens are re-registered automatically on rejoin. Streams terminate only on
explicit `leave()` or terminal `.transportFailure`.

**AND composition is available.** Use `filter.and(...)` or `Filter.all(...)`
for same-entry conjunction. OR remains a multi-registration pattern: register
multiple tokens and consume each stream. If two registrations overlap, the
backend sends one wire event with multiple matching IDs; the SDK fans that event
out to each matching token's stream.

**Postgres setup errors are asynchronous to join.** The backend can accept the
Phoenix join and then push a `system` error for `postgres_changes` setup
(missing publication/table, invalid column, malformed filter, cast failure).
The SDK should consume those setup messages before resolving `subscribe()` when
possible; if an error arrives later, the affected `postgresChanges(for:)` streams throw
`.postgresSubscriptionFailed(reason:)`.

**Gaps are possible on reconnect.** Tokens are re-registered on rejoin, but
there is no Postgres replay/cursor mechanism. Broadcast replay does not cover
Postgres changes.

### 5.4 Untyped escape hatch

For types without `@RealtimeTable`, the same register-then-subscribe flow
applies — only the filter and element types change.

```swift
// Use the dedicated untyped factory (per-event variant) — the schema+table
// arguments are strings; the filter is an `UntypedFilter`.
let deletes = await channel.deletes(
  schema: "public", table: "messages",
  filter: .eq("room_id", id)
)
// deletes: ChangeRegistration<Delete<JSONValue>>

try await channel.subscribe()

for try await record in await channel.postgresChanges(for: deletes) {
  // record: JSONValue — caller decodes manually
}
```

The untyped path produces the same `ChangeRegistration<E>` type the typed
factories return — only the variant's `T` differs (`JSONValue` instead of
your row type). Consumption via `channel.postgresChanges(for:)` is identical. Tokens
from typed and untyped factories can be mixed freely on the same channel.

---

## 6. Connection

### 6.1 Lazy open

```swift
public extension Realtime {
  /// Opens the WebSocket without joining any channel. Useful for pre-warming
  /// or surfacing auth errors before the first `subscribe()`. Idempotent:
  /// calling on an already-connected client returns immediately. Concurrent
  /// calls coalesce around a single in-flight connect.
  func connect() async throws(RealtimeError)
}
```

The WebSocket opens lazily on the first `channel.subscribe()` call. There is
no iteration-driven lazy-join in v3 — the only path from "no socket" to
"joined channel" is an explicit `subscribe()`. `channel.httpBroadcast` and
`realtime.httpBroadcastBatch` do not open the socket.

`realtime.connect()` is the explicit pre-warm path; it does not join any
channel.

### 6.2 Disconnect

```swift
public extension Realtime {
  /// Closes the socket and awaits close completion. Does NOT evict the channel
  /// cache or call leave() on any channel. Streams throw
  /// `.channelClosed(.clientDisconnected)`; subsequent operations trigger a
  /// fresh connect + rejoin.
  func disconnect() async
}
```

After a manual `disconnect()`, the `ReconnectionPolicy` does NOT auto-reopen
— the policy applies only to *unexpected* closes (transport failure, server
hangup). The next channel operation (`subscribe()`, send via a re-acquired
channel, or explicit `connect()`) triggers a fresh connect.

### 6.3 Mid-session token rotation

```swift
public extension Realtime {
  /// Update the access token used for future joins/HTTP private broadcasts and
  /// push it to currently joined channels via the Phoenix `access_token` event.
  func updateToken(_ newToken: String) async throws(RealtimeError)
}
```

`access_token` is a per-channel event. The backend does not ACK successful token
updates with `phx_reply`; `updateToken(_:)` returns after updating local state
and queueing the event to joined channels. If the new token is invalid, expired,
or loses required read policies, the backend pushes a `system` error and closes
the affected channel.

**Reactive path.** The backend does not emit a stable `token_expired` event.
Expiry is observed as a join rejection or `system` error followed by
`phx_close`. When that happens and an `accessToken` provider is configured, the
SDK fetches a fresh token and resubscribes affected channels. In-flight
operations are not retried on the same channel; they fail with
`.channelClosed(.unauthorized)` or `.authenticationFailed(...)` and callers use
the re-established channel for new work.

**If the access-token provider throws:** propagates as
`.authenticationFailed(underlying:)`. Connection enters
`.closed(.unauthorized)`. The `ReconnectionPolicy` does NOT apply — auth
recovery is caller-owned.

**On `connect()`:** the socket uses the literal `apiKey` and does not call the
access-token provider. Channel join calls the provider only for operations that
need an access token (private channels, RLS-backed features, or token refresh).

### 6.4 Status

```swift
public extension Realtime {
  /// Isolated — backed by connection state stored in the actor.
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
  /// When the *current* `state` was entered. Reset on every state transition.
  public let since: Date
  /// Last successful heartbeat round-trip time, if any. `nil` before the
  /// first heartbeat reply or after the connection drops.
  public let latency: Duration?
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
  case notSubscribed
  case channelClosed(CloseReason)
  case cannotRegisterAfterJoin   // postgres_changes registration after join (§5.3)
  case unknownToken              // postgresChanges(for:) called with a token from another channel (§5.3)

  case authenticationFailed(reason: String, underlying: (any Error & Sendable)?)

  case rateLimited(retryAfter: Duration?)
  case serverError(code: Int, message: String)
  case postgresSubscriptionFailed(reason: String)

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

**`.disconnected` vs `.channelClosed`.** `.disconnected` is thrown by
*operations attempted while the socket is down* — sends, broadcast acks,
explicit `connect()` failures during reconnect. The channel itself may
still be subscribed in the SDK; just not reachable on the wire right now.
`.channelClosed(reason)` is thrown by *streams whose channel has actually
terminated* — manual leave, server-initiated close, transport giveup.
Once a stream throws `.channelClosed`, it ends; `.disconnected` is
recoverable on reconnect.

**`.cannotRegisterAfterJoin`.** Thrown by `channel.changes(...)`,
`channel.inserts(...)`, etc. when the channel has already joined. Tokens
must be registered before the first `subscribe()` returns.

**`.notSubscribed`.** Thrown by live channel mutations and sends such as
WebSocket `broadcast` and `presence.track` when called before a successful
`subscribe()`. Stream factories may be created before subscribe and start
producing after the join succeeds.

**Backend error shapes are mixed.** Join failures usually arrive as
`phx_reply` errors. Runtime channel failures often arrive as a `system` event
with `extension`, `status`, `message`, and `channel`, then `phx_close`. HTTP
failures may be JSON errors, validation payloads, or empty responses. The SDK
maps these best-effort into `RealtimeError`; it does not rely on a stable
backend close-code taxonomy.

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
- **Presence is auto-restored.** The SDK re-sends the latest live presence
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
| `RealtimeClientV2(url:options:)`                | `Realtime(url:apiKey:accessToken:configuration:transport:)` |
| `client.channel("x")`                           | `realtime.channel("x")` (shared; explicit `leave()`)      |
| `await channel.subscribe()`                     | `try await channel.subscribe()`                           |
| `await channel.unsubscribe()`                   | `try await channel.leave()` (typed throws, global)        |
| `channel.broadcastStream(event:)`               | `channel.broadcasts(of: T.self, event:)` (typed stream)   |
| `await channel.broadcast(event:message:)`       | `try await channel.broadcast(payload, as: event)`         |
| — (no equivalent)                               | `channel.httpBroadcast(event:payload:)`                   |
| `channel.postgresChange(.all, …)`               | `let token = channel.changes(to: Message.self, …); try await channel.subscribe(); channel.postgresChanges(for: token)` |
| `channel.presenceChange()`                      | `channel.presence.diffs(T.self)` / `.observe(T.self)`     |
| `channel.track(...)`                            | `try await channel.presence.track(state)` → handle        |
| `ObservationToken` / `subscription.cancel()`    | `AsyncSequence` iteration ends on task cancel             |
| `accessToken: () async -> String?` closure      | `accessToken: { ... }` + `realtime.updateToken(…)` |
| `any Error`                                     | `RealtimeError` (typed throws everywhere)                 |
| `RealtimeClientOptions.maxRetryAttempts` etc.   | `Configuration.reconnection: ReconnectionPolicy`          |
| `options.vsn`                                   | `Configuration.protocolVersion` (default `.v2`)           |
| `options.handleAppLifecycle`                    | unchanged                                                 |

---

## 12. Locked Decisions

Everything below was resolved during design review and the backend source audit.
Kept here for reference so implementors don't re-litigate.

| # | Decision | Rationale |
| - | -------- | --------- |
| 1 | Channels are shared by topic within a `Realtime` instance | One server-side subscription per topic; predictable identity |
| 2 | No auto-unsubscribe on `deinit`; explicit `leave()` only | Explicit lifecycle; no ref-count magic |
| 3 | Global `leave()` — other holders' streams throw `.channelClosed(.userRequested)` | Mirrors the wire; surfaces the shared nature |
| 4 | `leave()` is `async throws`, awaits server channel close confirmation | Deterministic; consistent with the rest of the API |
| 5 | Pipelined re-acquire after `leave()` | Same-topic churn is transparent |
| 6 | Reconnect is silent in typed streams; `channel.state` is the lifecycle source of truth | Avoids leaky delivery-guarantee abstractions |
| 7 | Unbounded per-stream buffer (for now) | Simplest; `SlowConsumerPolicy` knob can be added additively |
| 8 | Fan-out is **per call**: each `broadcasts(of:event:)` / `postgresChanges(for:)` call is independent. A single returned stream is single-consumer (`AsyncStream` semantics); two consumers = two calls | Matches pub/sub intuition and Swift's stream model; iterating one returned stream twice would split values |
| 8a | `Realtime` and `Channel` are plain `actor`s (no `final`, no explicit `: Sendable` — both implicit) that own all their state. No separate Sendable side-store. Only the immutable `topic`/`options` constants and the `presence` accessor are `nonisolated`; everything else (`state`, `messages()`, `broadcasts`, `postgresChanges`, registration, `subscribe`, `leave`, sends, `httpBroadcast`, `presence.track`, `realtime.channel(_:)`, `realtime.status`) is isolated and `await`ed | Honest single-source-of-truth actor; avoids a parallel lock-protected store. Matches the repo's `public actor X` house style |
| 9 | Literal `apiKey: String` for connect; dynamic `accessToken` provider for JWT authorization; `updateToken(_:)` pushes access tokens to joined channels | Backend uses stable API keys for connect and rotating JWTs for channel/HTTP authorization |
| 10 | On token expiry/system auth close: refresh access token and resubscribe; do not retry the original push on the same channel | Backend closes the channel instead of ACKing a retryable `token_expired` operation |
| 11 | Access-token provider throwing does NOT trigger `ReconnectionPolicy` | Auth recovery is caller-owned |
| 12 | Composable AND filters per postgres_changes registration (typed `Filter<T>` or `UntypedFilter`); OR is modeled with multiple registrations | Reflects backend support for comma-separated AND clauses and backend `ids` routing for overlapping registrations |
| 13 | Both `Filter<T>` and `UntypedFilter` are structs with static factories; read like enums at call site | Typed path preserves `KeyPath<T, V>` + `V` binding; untyped path is a sibling type for raw column strings |
| 14 | `@RealtimeTable` macro for column-name resolution; manual conformance as escape hatch | Type-safe without forcing macros on every type |
| 14a | Postgres changes are **register-then-subscribe**: `channel.changes(...)` returns a `ChangeRegistration<E>` token; `channel.subscribe()` triggers the join with all pending tokens; consumption via `channel.postgresChanges(for: token)` | Phoenix requires postgres_changes filters in the join payload — the API can't pretend lazy join works for them |
| 14b | Variants are themselves generic over the row type (`Insert<T>`/`Update<T>`/`Delete<T>`/`AnyEvent<T>` conforming to `ChangeEventVariant`); registration is `ChangeRegistration<E>` (single generic, variant carries `T`); single `postgresChanges(for:)` overload dispatched on the variant | Cleaner type signatures than two-param `<T, E>` and a single overload covers typed and untyped paths |
| 14c | Registering after join throws `.cannotRegisterAfterJoin`; tokens are reusable across `leave()` + resubscribe cycles | Honest about the wire; ergonomic across reconnects and cycles |
| 14d | `subscribe()` is the **only** join path; no iteration-driven lazy-join | One mental model; no surprises from broadcast iteration silently joining |
| 14e | `subscribe()` returns `Void`; `Channel` remains the single surface for consumption, sending, presence, and leave | A separate subscription value cannot honestly guarantee live connectivity across reconnects or global leave |
| 14f | Raw feed is an isolated `func messages() -> AsyncStream<PhoenixMessage>` method (not a property, not an `AsyncSequence` conformance). `state` stays an isolated property | A method signals that each call mints a fresh stream; a property implying a stored value would mislead. Avoids a public iterator type and the awkward synchronous `makeAsyncIterator()` requirement on an actor |
| 14g | (merged into Decision 26) | — |
| 14h | Multiple `subscribe()` calls coalesce/idempotently join the same backing channel state | Topic identity (Decision 1) extends to joining |
| 14i | `Channel` drop without `leave()` does nothing (debug warning); leave is global as in Decision 3 | Consistency with channel rules; no auto-leave footguns under topic sharing |
| 14j | `Presence` accessor lives on `Channel`; `track` is runtime-gated by joined state | Same single-handle model as broadcast and Postgres changes |
| 14k | `PhoenixMessage` is fully raw — exposes `joinRef`, `ref`, `event`, `payload` (JSON or binary). Includes internal `phx_reply`/`phx_close`/`phx_error` frames | Direct iteration is the escape hatch for advanced consumers; SDK consumes the same frames internally for correlation |
| 14l | Separate liveness accessor **deferred** | `channel.state` is the lifecycle source of truth |
| 14m | After manual `leave()`, live `Channel` methods throw `.channelClosed(.userRequested)` and iteration terminates. Reconnects keep streams open; `.transportFailure` terminates them | Lifecycle is explicit without creating a stale subscription value |
| 14n | Filters split into two types: `Filter<T: RealtimeTable>` (KeyPath-based, compile-time-checked) and `UntypedFilter` (raw column strings + `any RealtimePostgresFilterValue`). Both serialize to backend filter clauses and can compose with AND | Untyped path needs raw column strings; typed path needs `RealtimeTable` for `columnName(for:)`; one type can't be both |
| 14o | Untyped factories (`channel.changes(schema:table:filter:)`, `inserts/updates/deletes(schema:table:filter:)`) return `ChangeRegistration<E<JSONValue>>`. Tokens from typed and untyped factories interoperate — same registration type, different variant `T` | Single consumption surface; mix freely on one channel |
| 15 | `PresenceHandle` is a regular class; explicit `cancel()`; debug warning on leak | Consistent with `Channel` lifecycle rule |
| 16 | One presence meta per channel process/key; repeated `track` updates that meta | Matches Realtime backend behavior for the same channel process and presence key |
| 17 | Presence key is channel-level only; server generates a fresh UUID per join when nil/empty | Simpler; per-track keys confuse more than they help |
| 18 | Auto re-track latest presence state on reconnect | Presence is a best-effort synced-state abstraction, but backend stores one meta per channel process/key |
| 19 | `withChannel` dropped entirely | Dangerous under global-leave semantics; 3-line explicit pattern is clearer |
| 20 | Flat `RealtimeError` enum; cancellation folded as `.cancelled` | Simpler call sites than grouped or union-throws |
| 21 | Underlying errors preserved as `any Error & Sendable` | Debug value outweighs Equatable/Codable loss |
| 22 | Single `broadcast` call site (with a `Data` overload for binary payloads, Decision 25); ack at channel-level config | Uniform call site |
| 23 | Self-broadcast is channel-level only (wire constraint) | Don't lie about the wire |
| 24 | Replay via `ChannelOptions.broadcast.replay`, private-channel-only | Backend replay is join-time-only and rejected on public channels |
| 25 | `Data` payloads bypass encoding; ship as binary frames | Natural Swift affordance |
| 26 | WebSocket broadcast send lives on `Channel` and is runtime-gated by subscribed state; one-shot HTTP sends without joining go via `channel.httpBroadcast` | The single-handle model is more honest than a subscription value that cannot guarantee a live connection |
| 27 | `channel.httpBroadcast(...)` for topic-scoped one-shot sends; `realtime.httpBroadcastBatch(...)` for multi-topic batches; both use HTTP auth semantics (`Authorization`/`apikey`) | The single-message operation belongs to the topic handle; batch remains client-level because it can span topics |
| 28 | Socket opens lazily on first channel join | Zero ceremony for common paths; explicit `connect()` still exists |
| 29 | `disconnect()` closes socket, keeps channel cache | Pause/resume, not total teardown |
| 30 | `disconnect()` is `async`, awaits close completion | Consistent with other terminal operations |
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
| 45 | Presence key default: server-generated UUID per join when nil/empty | Matches Realtime backend behavior |

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

/// Wire payload for the "chat" broadcast event — distinct from `Message`,
/// which is the persisted postgres row consumed via `postgresChanges(for:)`.
struct ChatBroadcast: Codable, Sendable {
  let authorId: UUID
  let text: String
}

struct UserPresence: Codable, Sendable {
  let userId: UUID
  let status: Status
  enum Status: String, Codable, Sendable { case active, idle }
}

@MainActor @Observable
final class ChatRoomModel {
  private let realtime: Realtime
  private let roomId: UUID
  private let me: UUID
  private var channel: Channel?
  private var runTask: Task<Void, Never>?
  private var trackHandle: PresenceHandle?

  var messages: [Message] = []
  var onlineUsers: [UUID: UserPresence] = [:]
  var connection: ConnectionStatus.State = .idle

  init(realtime: Realtime, roomId: UUID, me: UUID) {
    self.realtime = realtime
    self.roomId = roomId
    self.me = me
  }

  func start() {
    runTask = Task { [realtime, roomId, me, weak self] in
      do {
        // Acquire the channel (isolated: touches the topic registry).
        let channel = await realtime.channel("chat:room:\(roomId)") {
          $0.presence.enabled = true
          $0.presence.key = "user-\(me)"
        }
        await MainActor.run { self?.channel = channel }

        // Register postgres tokens BEFORE subscribe — they bake into phx_join.
        let messageInserts = await channel.inserts(
          into: Message.self, where: .eq(\.roomId, roomId)
        )

        // Single explicit join captures the registration above.
        try await channel.subscribe()

        try await withThrowingDiscardingTaskGroup { group in
          // Postgres inserts → append
          group.addTask {
            let rows = await channel.postgresChanges(for: messageInserts)
            for try await row in rows {
              await MainActor.run { self?.messages.append(row) }
            }
          }
          // Presence observers
          group.addTask {
            for await state in channel.presence.observe(UserPresence.self) {
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
            let handle = try await channel.presence.track(
              UserPresence(userId: me, status: .active)
            )
            await MainActor.run { self?.trackHandle = handle }
          }
          // Connection status mirror
          group.addTask {
            for await status in await realtime.status {
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

  /// Broadcast through the active channel. No-op before the channel exists;
  /// throws `.notSubscribed` if created but not yet joined.
  func send(_ text: String) async throws(RealtimeError) {
    guard let channel else { return }
    try await channel.broadcast(
      ChatBroadcast(authorId: me, text: text),
      as: "chat"
    )
  }

  func stop() async {
    runTask?.cancel()
    try? await trackHandle?.cancel()
    try? await channel?.leave()
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
