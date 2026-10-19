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
  instead (see [Errors](#errors)).
- **Cancellation throws `CancellationError`.** A cancelled `httpSend` used to throw
  `URLError(.cancelled)`. Search for `URLError` near `httpSend` and catch `CancellationError`.
- **Status values keep unknown raw values.** `RealtimeMessageV2.status` used to be `nil` for a
  reply status the SDK did not know. It now returns a `PushStatus` with that raw value.
  `X(rawValue:) != nil` checks on the status types are now always `true`.
- **Status text changed.** `"\(status)"` on `RealtimeClientStatus` now prints `connected`, not
  `Connected`. On the other status types it prints the struct description. Use `.rawValue`.
- **`SupabaseClient` sets the Realtime logger.** A `logger:` you pass in
  `SupabaseClientOptions(realtime:)` is replaced by the global logger. Create `RealtimeClientV2`
  yourself if Realtime needs its own logger.
- **No global `URLSession` for the WebSocket.** Realtime no longer takes the global session. If
  you need one (for example for certificate pinning), pass it as
  `SupabaseClientOptions(realtime: .init(session: mySession))`.
- **Reconnect delays have jitter.** Each reconnect waits a random time between half the delay
  and the full delay, capped at 30 seconds. It never waits longer than before.

## Renames and type changes

| v2 | v3 |
| --- | --- |
| `import RealtimeV2` | `import Realtime` |
| `RealtimeClient`, `RealtimeChannel`, `Presence` (v1 API) | `RealtimeClient`, `RealtimeChannel` (actors, see below), `PresenceV2` |
| `RealtimeClientV2`, `RealtimeChannelV2` | `RealtimeClient`, `RealtimeChannel` |
| `RealtimeClientV2.subscriptions` | `RealtimeClient.channels` |
| `RealtimeClientV2.Configuration` | `RealtimeClientOptions` |
| `RealtimeClientV2.init(config:)` | `RealtimeClient.init(url:options:)` |
| `RealtimeClientV2.addChannel(_:)` | removed; the client tracks channels |
| `RealtimeClientV2.Status` | `RealtimeClientStatus` |
| `RealtimeClientV2.connect()` | `connect() async throws` |
| `RealtimeClientV2.disconnect()` | `disconnect() async` |
| `RealtimeClientV2.statusChange`, `onStatusChange(_:)` | `statusChanges`, `statusSnapshot` |
| `RealtimeClientV2.heartbeat`, `onHeartbeat(_:)` | `heartbeats` |
| `RealtimeChannelV2.Status` | `RealtimeChannelStatus` |
| `RealtimeChannelV2.Subscription`, `RealtimeSubscription`, `ObservationToken` | removed; cancel the task that reads the stream |
| `RealtimeChannelV2.subscribe()`, `subscribeWithError()` | `subscribe() async throws` |
| `RealtimeChannelV2.updateAuth(jwt:)` | `RealtimeClient.setAuth(_:)` |
| `RealtimeChannelV2.statusChange`, `onStatusChange(_:)` | `statusChanges`, `statusSnapshot` |
| `onBroadcast(event:callback:)`, `broadcastStream(event:)`, `broadcast(event:) -> AsyncStream` | `broadcasts(event:)` |
| `broadcastDataStream(event:)` | `broadcastData(event:)` |
| `onPostgresChange(_:...)`, `postgresChange(_:schema:table:filter: String?)` | `postgresChanges(_:schema:table:filter: RealtimePostgresFilter?)` |
| `onPresenceChange(_:)`, `presenceChange()` | `presenceChanges()` |
| `onSystem(callback:)`, `system()` | `systemMessages()` |
| `broadcast(event:message:)`, `broadcast(event:data:)`, `track(_:)`, `untrack()` (`async`) | `async throws`; wait for the server reply when `acknowledgeBroadcasts` is on |
| `PushStatus.timeout` | removed; a push that gets no reply throws `RealtimeError` with `kind == .timeout` |
| `RealtimeMessageV2.eventType: EventType?` | `eventType: EventType` (not optional) |
| `RealtimeMessageV2.EventType.tokenExpired` | `.system`; check the payload |
| `RealtimeClientOptions(fetch:)` | `RealtimeClientOptions(http:)` |
| `RealtimeClientOptions(logger: (any SupabaseLogger)?)` | `logger: Logging.Logger` |
| `RealtimeClientOptions(vsn:)`, `RealtimeProtocolVersion` | removed; protocol 2.0.0 always |
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

## `RealtimeClient` and `RealtimeChannel` are actors

Both types are now actors that share one executor. Most calls need `await`, including
`channel(_:options:)` on the client and on `SupabaseClient`, and the stream methods on a
channel. `statusSnapshot` and `statusChanges` do not need `await`.

```swift
// v2
let channel = supabase.channel("room")
let messages = channel.broadcastStream(event: "message")
try await channel.subscribeWithError()
// v3
let channel = await supabase.channel("room")
let messages = await channel.broadcasts(event: "message")
try await channel.subscribe()
```

`connect()` now throws when the socket cannot be opened, and `disconnect()` is `async`.

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
  for await payload in await channel.broadcasts(event: "message") {
    print(payload)
  }
}
defer { task.cancel() }
```

Open `postgresChanges` and `presenceChanges` streams before `subscribe()`. They shape the join
request. Opening one after the join reports an issue and returns an empty stream. Presence is
sent to the server only when a `presenceChanges()` stream is open.

## Pushes throw instead of returning a status

`broadcast(event:message:)`, `broadcast(event:data:)`, `track(_:)` and `untrack()` are
`async throws`. They return once the frame is sent. When `acknowledgeBroadcasts` is on they wait
for the server reply first, and the reply becomes the result of the call:

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
