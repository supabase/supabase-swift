# Realtime v3 migration

This file covers the changes to the `Realtime` module from v2.55.4 to v3. See
[the v3 migration overview](../../../V3_MIGRATION.md) for steps that apply to every module.

> [!NOTE]
> Realtime is still being reworked for v3. The Realtime API may still change before v3.0.0.

## Silent changes

Changes that still compile but behave differently. Check each one by hand.

- **Errors are `RealtimeError`.** `subscribeWithError()`, `httpSend` and connection failures now
  throw a public `RealtimeError` with a `kind`. Code that compared `localizedDescription` or
  checked an `NSError` domain stops matching. Search for those checks and match on `kind`
  instead (see [Errors](#errors)). A join the server rejects throws with the server's reason in
  `message`.
- **Cancellation throws `CancellationError`.** A cancelled `httpSend` used to throw
  `URLError(.cancelled)`. Search for `URLError` near `httpSend` and catch `CancellationError`.
- **Reconnect waits are shorter and spread out.** `defaultReconnectDelay` is 1 s (was 7 s), and
  the n-th wait is a random duration in `0...min(30s, reconnectDelay · 2^(n-1))` (was exactly
  `min(30s, reconnectDelay · 2^(n-1))`). Code that relied on a minimum wait before a reconnect
  must not.
- **`connect()` during a reconnect tries at once.** It no longer waits out the backoff of the
  automatic reconnect. It returns when the socket opens, and throws only when the client stops
  reconnecting (see "Reconnect stops on a refused handshake" below) or
  `disconnect(code:reason:)` runs. A failed attempt goes back to the backoff, and `connect()`
  keeps waiting, for as long as the server cannot be reached. Cancel the calling task to stop
  waiting.
- **Status values keep unknown raw values.** `RealtimeMessageV2.status` used to be `nil` for a
  reply status the SDK did not know. It now returns a `PushStatus` with that raw value.
  `X(rawValue:) != nil` checks on the status types are now always `true`.
- **Status text changed.** `"\(status)"` on `RealtimeClientStatus` now prints `connected`, not
  `Connected`. On the other status types it prints the struct description. Use `.rawValue`.
- **`SupabaseClient` sets the Realtime logger.** A `logger:` you pass in
  `SupabaseClientOptions(realtime:)` is replaced by the global logger. Create `RealtimeClient`
  yourself if Realtime needs its own logger.
- **No global `URLSession` for the WebSocket.** Realtime no longer takes the global session. If
  you need one (for example for certificate pinning), pass it as
  `SupabaseClientOptions(realtime: .init(session: mySession))`.
- **Reconnect stops on a refused handshake.** v2 tried to reconnect forever, and v3 still does
  after a dropped connection or a failed attempt. v3 stops at once when the WebSocket handshake
  gets HTTP 401, 403 or 404, or when the server closes the socket with a code of 4000 or above.
  The client status then stays `.disconnected`, `connect()` throws, and a pending
  `subscribeWithError()` throws. Search for code that expects the client to recover on its own
  from a bad API key or token. Call `connect()` again, for example after `setAuth(_:)`.
- **A failed connection attempt counts against `maxRetryAttempts`.** As in v2,
  `maxRetryAttempts` bounds the attempts of one `subscribeWithError()`, not the client, and the
  client keeps reconnecting after the subscribe throws `kind == .maxRetryAttemptsReached`. Each
  failed connection attempt counts, and so does each join that timed out or failed. The waits
  between connection attempts are the reconnect waits above, so a subscribe while the server is
  down can throw sooner than in v2.
- **The `accessToken` callback is called less often, and before the token expires.** The client
  calls it at most once every 10 seconds from `setAuth()`, the heartbeat, a reconnect, and
  `httpSend`. Inside that window `setAuth()` keeps the current token. A subscribe still calls it,
  so a channel that subscribes right after sign-in joins with the new token. While connected, the
  client also calls it one minute before a JWT's `exp`. A `nil` result keeps the current token
  instead of sending a `null` token to the channels. The callback runs in a task of its own, so
  cancelling `subscribeWithError()` or `setAuth()` no longer cancels it. After half of `timeout`
  it counts as failed and is cancelled, so a callback that hangs no longer stops a reconnect.
  Search for `setAuth()` calls that expect the callback to run every time.
- **A join waits at least 10 seconds.** Each join attempt waits at least
  `RealtimeClientOptions.defaultTimeout` (10 seconds) for the server's reply, even when
  `timeout` is shorter. The server can hold a rejected private-channel join for about 5 seconds.
  With a short `timeout`, `subscribeWithError()` now takes longer to fail, and `unsubscribe()`
  and `removeChannel(_:)` wait as long for an unanswered leave. Pushes and `httpSend` still use
  `timeout`.
- **`disconnect()` keeps the channels.** After `disconnect()`, each channel stays in `channels`,
  its status is `.subscribing`, and it joins again on the next `connect()`.
  `subscribeWithError()` on such a channel connects again, unless `connectOnSubscribe` is off,
  and returns once the channel joined. A `subscribeWithError()` that is still waiting for its
  first join throws `kind == .notConnected`. Call `removeChannel(_:)` or `removeAllChannels()`
  to drop channels.
- **Mismatched `postgres_changes` bindings throw.** When the server answers a join with
  `postgres_changes` bindings that differ from the ones the channel sent, v2 subscribed and the
  `postgresChange` streams got no rows. v3 unsubscribes and `subscribeWithError()` throws
  `kind == .postgresChangesMismatch`. Check the schema, table and filter of each
  `postgresChange` stream.
- **A removed channel cannot subscribe.** `subscribeWithError()` on a channel after
  `removeChannel(_:)` throws `kind == .channelClosed` with `isRetryable == false`. Get a new
  channel from `channel(_:options:)`. It returns a new channel as soon as `removeChannel(_:)`
  starts.

## Renames and type changes

| v2 | v3 |
| --- | --- |
| `import RealtimeV2` | `import Realtime` |
| `RealtimeClient`, `RealtimeChannel`, `Presence` (v1 API) | `RealtimeClient`, `RealtimeChannel`, `PresenceV2` |
| `RealtimeClientV2`, `RealtimeChannelV2` | `RealtimeClient`, `RealtimeChannel` |
| `RealtimeClientV2.subscriptions` | `RealtimeClient.channels` |
| `RealtimeClientV2.Configuration` | `RealtimeClientOptions` |
| `RealtimeClientV2.init(config:)` | `RealtimeClient.init(url:options:)` |
| `RealtimeClientV2.addChannel(_:)` | removed; `channel(_:options:)` makes and tracks every channel |
| `RealtimeClientV2.push(_:)` | removed; use `broadcast`, `track` or `httpSend` on a channel |
| `RealtimeClientV2.Status` | `RealtimeClientStatus` |
| `RealtimeClientV2.connect() async` | `connect() async throws` |
| `RealtimeClientV2.disconnect(code:reason:)` | `disconnect(code:reason:) async` |
| `RealtimeClientV2.onStatusChange(_:)` | `statusChange` |
| `RealtimeClientV2.onHeartbeat(_:)` | `heartbeat` |
| `HeartbeatStatus.disconnected` | removed; read `RealtimeClient.statusChange` |
| `RealtimeChannelV2.Status` | `RealtimeChannelStatus` |
| `RealtimeChannelV2.Subscription`, `RealtimeSubscription` | removed; cancel the task that reads the stream |
| `RealtimeChannelV2.subscribe()` | `subscribeWithError()` |
| `RealtimeChannelV2.updateAuth(jwt:)` | `RealtimeClient.setAuth(_:)`, which updates every channel |
| `RealtimeChannelV2.onStatusChange(_:)` | `statusChange` |
| `onBroadcast(event:callback:)`, `broadcast(event:) -> AsyncStream` | `broadcastStream(event:)` |
| `onBroadcastData(event:callback:)` | `broadcastDataStream(event:)` |
| `onPostgresChange(_:schema:table:filter:callback:)` | `postgresChange(_:schema:table:filter:select:)` |
| `postgresChange(_:schema:table:filter: String?)` | `postgresChange(_:schema:table:filter: .raw(_:))` |
| `onPresenceChange(_:)` | `presenceChange()` |
| `onSystem(callback:)` | `system()` |
| `ChannelEvent` | removed; use the event strings, such as `"broadcast"` |
| `broadcast(event:message: JSONObject)`, `broadcast(event:data:)`, `track(state:)`, `untrack()` (`async`) | `async throws`; wait for the server reply when `acknowledgeBroadcasts` is on |
| `PushStatus.timeout` | removed; a push that gets no reply throws `RealtimeError` with `kind == .timeout` |
| `RealtimeMessageV2.eventType: EventType?` | `eventType: EventType` (not optional) |
| `RealtimeMessageV2.EventType.tokenExpired` | `.system`; check the payload |
| `RealtimeClientOptions(fetch:)` | `RealtimeClientOptions(http:)` |
| `RealtimeClientOptions(logger: (any SupabaseLogger)?)` | `logger: Logging.Logger` |
| `RealtimeClientOptions(vsn:)`, `RealtimeProtocolVersion` | removed; protocol 2.0.0 always |
| `RealtimeClientOptions(disconnectOnSessionLoss:)`, `defaultDisconnectOnSessionLoss` | removed; v2 never read it |
| `RealtimeClientOptions(timeoutInterval:)` | `timeout:` |
| `heartbeatInterval:`, `reconnectDelay:`, `disconnectOnEmptyChannelsAfter:` (`TimeInterval`) | same names, `Duration` |
| `defaultTimeoutInterval` | `defaultTimeout` |
| `defaultHeartbeatInterval`, `defaultReconnectDelay`, `defaultDisconnectOnEmptyChannelsAfter` (`TimeInterval`) | same names, `Duration` |
| `httpSend(...timeout: TimeInterval?)` | `httpSend(...timeout: Duration?)` |
| `PostgresAction.record`, `.oldRecord` (`[String: AnyJSON]`) | `[String: JSONValue]` |
| `RealtimeClientStatus`, `RealtimeChannelStatus`, `HeartbeatStatus`, `PushStatus`, `LogLevel`, `RealtimeMessageV2.EventType` (`enum`) | `struct`, same member names |
| `Column`, `PresenceV2` (`Codable`) | `Decodable` |
| `ReplayOption`, `BroadcastJoinConfig`, `PresenceJoinConfig` (`Codable`) | `Encodable` |
| `RealtimeMessageV2` (`Codable`) | not `Codable` |

A `switch` over one of the status structs needs a `default:` case. `init(rawValue:)` is no
longer failable, so drop `if let` around it.

Remove `vsn:`. The client always uses protocol 2.0.0, so the server must be Realtime v2.63.0 or
later. Upgrade a self-hosted Realtime before you upgrade the SDK.

The v1 API is removed. See [the RealtimeV2 migration guide](../RealtimeV2%20Migration%20Guide.md)
to move from v1 to the v2 API first, then apply this guide.

## Streams replace callbacks

The `on*` callback methods and `RealtimeSubscription` tokens are removed. Read the matching
`AsyncStream` instead. Cancel the task that reads it to stop listening. Removing the channel
ends every stream.

```swift
// v2
let subscription = channel.onBroadcast(event: "message") { payload in
  print(payload)
}
defer { subscription.cancel() }
// v3
let task = Task {
  for await payload in channel.broadcastStream(event: "message") {
    print(payload)
  }
}
defer { task.cancel() }
```

Open `postgresChange` and `presenceChange()` streams before `subscribeWithError()`. They shape
the join request. Opening one after the join reports an issue and returns an empty stream.
Presence is sent to the server only when a `presenceChange()` stream is open.

## `postgresChange` takes a typed filter

The `filter: String?` overloads are removed. Use a `RealtimePostgresFilter` case, or pass the
string as written with `.raw(_:)`.

```swift
// v2
let changes = channel.postgresChange(
  InsertAction.self, table: "messages", filter: "room_id=eq.\(roomID)"
)
// v3
let changes = channel.postgresChange(
  InsertAction.self, table: "messages", filter: .eq("room_id", value: roomID)
)
let sameChanges = channel.postgresChange(
  InsertAction.self, table: "messages", filter: .raw("room_id=eq.\(roomID)")
)
```

## Pushes throw instead of returning a status

`broadcast(event:message:)`, `broadcast(event:data:)`, `track(_:)`, `track(state:)` and
`untrack()` are `async throws`. They return once the frame is sent. When
`acknowledgeBroadcasts` is on they wait for the server reply first, and the reply becomes the
result of the call:

- The server acknowledged the push: the call returns.
- No reply came within the client's `timeout`: the call throws `RealtimeError` with
  `kind == .timeout`.
- The server rejected the push: the call throws `RealtimeError` with the server's reason in
  `message`, `kind == .payloadTooLarge` for an oversized payload and `.server` otherwise, and
  `serverCode` set when the reason starts with a code.
- The channel left or the socket closed while waiting: `kind == .notSubscribed` or
  `.notConnected`.
- The server closed the channel while waiting: `kind == .channelClosedByServer`.

Wrap the call in a `Task` to send without waiting. Cancelling that task stops the wait and
throws `CancellationError`; the frame itself is not recalled.

```swift
// v2
try await channel.broadcast(event: "ping", message: ["n": 1])
// v3
do {
  try await channel.broadcast(event: "ping", message: ["n": 1])
} catch let error as RealtimeError where error.kind == .timeout {
  // no acknowledgement in time
}
```

A WebSocket `broadcast` on a channel that is not subscribed no longer falls back to the REST
endpoint. It throws `kind == .notSubscribed`. Use `httpSend` to broadcast without a
subscription.

## Intervals are `Duration`

Pass `Duration` values. Convert a `TimeInterval` with `.seconds(value)`.

```swift
// v2
let options = RealtimeClientOptions(heartbeatInterval: 30, reconnectDelay: 5, timeoutInterval: 15)
try await channel.httpSend(event: "ping", message: ["n": 1], timeout: 3)
// v3
let options = RealtimeClientOptions(
  heartbeatInterval: .seconds(30), reconnectDelay: .seconds(5), timeout: .seconds(15)
)
try await channel.httpSend(event: "ping", message: ["n": 1], timeout: .seconds(3))
```

## `fetch:` is replaced by `http:`

REST broadcast calls go through a `ClientTransport`.

```swift
// v2
let options = RealtimeClientOptions(fetch: { try await session.data(for: $0) })
// v3
let options = RealtimeClientOptions(http: .init(transport: URLSessionTransport(session: session)))
```

## `RealtimeMessageV2` is not `Codable`

Build the JSON from the fields if you encoded messages yourself. Code that passes a message to
`JSONSerialization` or another `Any`-based encoder still compiles but fails at run time.

```swift
// v2
let data = try JSONEncoder().encode(message)
// v3
let json: JSONObject = [
  "event": .string(message.event),
  "join_ref": message.joinRef.map(JSONValue.string) ?? .null,
  "payload": .object(message.payload),
  "ref": message.ref.map(JSONValue.string) ?? .null,
  "topic": .string(message.topic),
]
let data = try JSONEncoder().encode(json)
```

## Errors

Catch `RealtimeError` and match on `kind`. A non-202 `httpSend` reply is `.server` with
`response` set. A network or WebSocket failure is `.transport` with the cause in
`underlyingError`.

```swift
// v2
do {
  try await channel.subscribeWithError()
} catch {
  if error.localizedDescription == "Maximum retry attempts reached." { scheduleRetry() }
}
// v3
do {
  try await channel.subscribeWithError()
} catch let error as RealtimeError where error.kind == .maxRetryAttemptsReached {
  scheduleRetry()
}
```
