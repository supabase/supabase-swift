# Realtime v3 — Phase 5, 6 & 7 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement broadcast (Phase 5), presence (Phase 6), and Postgres changes (Phase 7) on top of the Channel actor from Phase 4.

**Architecture:** Each feature adds an `AsyncThrowingStream`-based fan-out API to `Channel` via extension files. The `Channel` actor owns the continuation dictionaries; extensions register/unregister continuations and deliver messages. All streams auto-join on first iteration. `Filter<T>` uses `KeyPath`-based compile-time column name resolution; `RealtimeTable` is a protocol with manual conformance.

**Prerequisite:** Phases 1–4 complete and committed.

---

## Task 1: Broadcast (Phase 5)

**Files:**
- Create: `Packages/_Realtime/Sources/_Realtime/Broadcast/BroadcastMessage.swift`
- Create: `Packages/_Realtime/Sources/_Realtime/Broadcast/Channel+Broadcast.swift`
- Create: `Packages/_Realtime/Sources/_Realtime/Broadcast/Realtime+HTTP.swift`
- Create: `Packages/_Realtime/Tests/_RealtimeTests/BroadcastTests.swift`

- [ ] **Step 1: Write failing broadcast tests**

```swift
import Testing
import ConcurrencyExtras
@testable import _Realtime

@Suite struct BroadcastTests {
  static let testURL = URL(string: "ws://localhost:4000/realtime/v1")!

  // Helper: connect + auto-reply to phx_join
  func makeConnectedRealtime() async throws -> (Realtime, InMemoryServer) {
    let (transport, server) = InMemoryTransport.pair()
    let realtime = Realtime(url: Self.testURL, apiKey: .literal("key"), transport: transport)
    try await realtime.connect()

    Task {
      for await frame in server.receivedFrames {
        guard let text = frame.text,
              let msg = try? PhoenixSerializer.decodeText(text),
              msg.event == "phx_join" else { continue }
        let reply = PhoenixMessage(
          joinRef: msg.joinRef, ref: msg.ref, topic: msg.topic,
          event: "phx_reply", payload: ["status": "ok", "response": .object([:])
        ])
        await server.send(.text(try! PhoenixSerializer.encodeText(reply)))
      }
    }
    return (realtime, server)
  }

  @Test func broadcastDeliveredToTypedStream() async throws {
    struct Msg: Decodable, Sendable { let text: String }
    let (realtime, server) = try await makeConnectedRealtime()
    let channel = realtime.channel("room:1")

    let stream = await channel.broadcasts(of: Msg.self, event: "chat")
    var received: [Msg] = []

    Task {
      for try await msg in stream { received.append(msg) }
    }

    // Wait for join
    try await Task.sleep(for: .milliseconds(50))

    // Server pushes a broadcast
    let payload: [String: JSONValue] = ["event": "chat", "payload": .object(["text": "hello"]), "type": "broadcast"]
    let push = PhoenixMessage(joinRef: nil, ref: nil, topic: "room:1", event: "broadcast", payload: payload)
    await server.send(.text(try! PhoenixSerializer.encodeText(push)))

    try await Task.sleep(for: .milliseconds(50))
    #expect(received.count == 1)
    #expect(received.first?.text == "hello")
  }

  @Test func broadcastFanoutToMultipleSubscribers() async throws {
    let (realtime, server) = try await makeConnectedRealtime()
    let channel = realtime.channel("room:2")

    let s1 = await channel.broadcasts()
    let s2 = await channel.broadcasts()
    var count1 = 0; var count2 = 0

    Task { for try await _ in s1 { count1 += 1 } }
    Task { for try await _ in s2 { count2 += 1 } }

    try await Task.sleep(for: .milliseconds(50))

    let payload: [String: JSONValue] = ["event": "e", "payload": .object([:]), "type": "broadcast"]
    let push = PhoenixMessage(joinRef: nil, ref: nil, topic: "room:2", event: "broadcast", payload: payload)
    await server.send(.text(try! PhoenixSerializer.encodeText(push)))

    try await Task.sleep(for: .milliseconds(50))
    #expect(count1 == 1)
    #expect(count2 == 1)
  }

  @Test func broadcastThrowsChannelNotJoinedIfNotJoined() async throws {
    let (transport, _) = InMemoryTransport.pair()
    let realtime = Realtime(url: Self.testURL, apiKey: .literal("key"), transport: transport)
    try await realtime.connect()
    let channel = realtime.channel("room:3")

    struct Msg: Encodable, Sendable { let x: Int }
    do {
      try await channel.broadcast(Msg(x: 1), as: "event")
      Issue.record("Expected channelNotJoined")
    } catch RealtimeError.channelNotJoined {
      // expected
    }
  }
}
```

- [ ] **Step 2: Run — expect compile failure**

```bash
cd Packages/_Realtime && swift test --filter BroadcastTests 2>&1 | head -10
```

- [ ] **Step 3: Create `Broadcast/BroadcastMessage.swift`**

```swift
import Foundation

public struct BroadcastMessage: Sendable {
  public let event: String
  public let payload: JSONValue
  public let receivedAt: Date
}
```

- [ ] **Step 4: Create `Broadcast/Channel+Broadcast.swift`**

```swift
import Foundation

extension Channel {
  /// Typed event stream — decodes each broadcast payload to `T`. Auto-joins on first iteration.
  public func broadcasts<T: Decodable & Sendable>(
    of type: T.Type = T.self,
    event: String,
    decoder: JSONDecoder? = nil
  ) -> AsyncThrowingStream<T, RealtimeError> {
    let raw = broadcasts()
    let dec = decoder ?? JSONDecoder()
    return AsyncThrowingStream { continuation in
      Task {
        do {
          for try await msg in raw {
            guard let eventVal = msg.payload["event"],
                  case .string(let evtName) = eventVal,
                  evtName == event else { continue }
            guard let payloadVal = msg.payload["payload"],
                  case .object(let obj) = payloadVal else { continue }
            do {
              let data = try JSONEncoder().encode(obj)
              let decoded = try dec.decode(T.self, from: data)
              continuation.yield(decoded)
            } catch {
              continuation.finish(throwing: .decoding(type: String(describing: T.self), underlying: error as! (any Error & Sendable)))
              return
            }
          }
          continuation.finish()
        } catch let e as RealtimeError {
          continuation.finish(throwing: e)
        }
      }
    }
  }

  /// Untyped stream — raw payloads for all broadcast events. Auto-joins on first iteration.
  public func broadcasts() -> AsyncThrowingStream<BroadcastMessage, RealtimeError> {
    AsyncThrowingStream { continuation in
      let id = UUID()
      Task {
        // Register continuation on the actor
        await registerBroadcastContinuation(id: id, continuation: continuation)
        continuation.onTermination = { [id] _ in
          Task { await self.broadcastContinuations.removeValue(forKey: id) }
        }
        // Auto-join
        do { try await joinIfNeeded() }
        catch let e as RealtimeError { continuation.finish(throwing: e) }
      }
    }
  }

  // Internal — called by Realtime when routing incoming broadcast frames
  func deliverBroadcast(_ payload: [String: JSONValue]) {
    let msg = BroadcastMessage(
      event: (payload["event"].flatMap { if case .string(let s) = $0 { s } else { nil } }) ?? "",
      payload: payload["payload"] ?? .null,
      receivedAt: Date()
    )
    for cont in broadcastContinuations.values { cont.yield(msg) }
  }

  /// Send a typed broadcast. Throws `.channelNotJoined` if not joined.
  public func broadcast<T: Encodable & Sendable>(_ payload: T, as event: String) async throws(RealtimeError) {
    guard currentState == .joined else { throw .channelNotJoined }
    guard let realtime else { throw .disconnected }
    let encoder = await realtime.configuration.encoder
    let data: Data
    do { data = try encoder.encode(payload) }
    catch { throw .encoding(underlying: error as! (any Error & Sendable)) }
    guard let obj = try? JSONDecoder().decode([String: JSONValue].self, from: data) else {
      throw .encoding(underlying: EncodingError.invalidValue(payload, .init(codingPath: [], debugDescription: "Not a JSON object")))
    }
    let msg = PhoenixMessage(
      joinRef: joinRef, ref: nil,
      topic: topic, event: "broadcast",
      payload: ["event": .string(event), "payload": .object(obj)]
    )
    if await realtime.configuration.broadcast.acknowledge {
      _ = try await realtime.sendAndAwait(msg, timeout: await realtime.configuration.broadcastAckTimeout)
    } else {
      try await realtime.send(msg)
    }
  }

  /// Send raw `Data` as a binary broadcast frame. Throws `.channelNotJoined` if not joined.
  public func broadcast(_ data: Data, as event: String) async throws(RealtimeError) {
    guard currentState == .joined else { throw .channelNotJoined }
    guard let realtime else { throw .disconnected }
    let frame = try {
      do { return try PhoenixSerializer.encodeBroadcastPush(joinRef: joinRef, ref: nil, topic: topic, event: event, binaryPayload: data) }
      catch { throw RealtimeError.encoding(underlying: error as! (any Error & Sendable)) }
    }()
    try await realtime.sendBinary(frame)
  }

  // MARK: - Private helpers

  private func registerBroadcastContinuation(
    id: UUID,
    continuation: AsyncThrowingStream<BroadcastMessage, RealtimeError>.Continuation
  ) {
    broadcastContinuations[id] = continuation
  }

  private func joinIfNeeded() async throws(RealtimeError) {
    if currentState == .unsubscribed { try await join() }
  }
}

// Expose sendBinary on Realtime
extension Realtime {
  func sendBinary(_ data: Data) async throws(RealtimeError) {
    guard let connection else { throw .disconnected }
    do { try await connection.send(.binary(data)) }
    catch { throw .transportFailure(underlying: error as! (any Error & Sendable)) }
  }
}
```

Update `Channel.handle(_:)` in `Channel.swift` to call `deliverBroadcast` instead of iterating directly:

```swift
case "broadcast":
  deliverBroadcast(msg.payload)
```

- [ ] **Step 5: Create `Broadcast/Realtime+HTTP.swift`**

```swift
import Foundation

extension Realtime {
  /// One-shot broadcast via HTTP. Does not open the WebSocket.
  public func httpBroadcast<T: Encodable & Sendable>(
    topic: String,
    event: String,
    payload: T,
    isPrivate: Bool = false
  ) async throws(RealtimeError) {
    let msg = HttpBroadcastMessage(topic: topic, event: event, payload: payload, isPrivate: isPrivate)
    try await httpBroadcast([msg])
  }

  /// Batch HTTP broadcast.
  public func httpBroadcast(_ messages: [HttpBroadcastMessage]) async throws(RealtimeError) {
    let token: String
    do { token = try await resolveToken() }
    catch { throw .authenticationFailed(reason: error.localizedDescription, underlying: nil) }

    var httpURL = url
    // Replace ws(s):// with http(s)://
    if var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
      comps.scheme = comps.scheme == "wss" ? "https" : "http"
      comps.path = "/realtime/v1/api/broadcast"
      comps.queryItems = nil
      httpURL = comps.url ?? url
    }

    let body: [[String: JSONValue]] = messages.map { m in
      var entry: [String: JSONValue] = [
        "topic": .string(m.topic),
        "event": .string(m.event),
      ]
      if m.isPrivate { entry["private"] = true }
      // Encode payload to JSON object
      if let data = try? configuration.encoder.encode(m.payload),
         let obj = try? JSONDecoder().decode([String: JSONValue].self, from: data) {
        entry["payload"] = .object(obj)
      }
      return entry
    }

    guard let bodyData = try? JSONEncoder().encode(["messages": body]) else {
      throw .encoding(underlying: EncodingError.invalidValue(messages, .init(codingPath: [], debugDescription: "Encoding failed")))
    }

    var request = URLRequest(url: httpURL)
    request.httpMethod = "POST"
    request.httpBody = bodyData
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(token, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    let (_, response): (Data, URLResponse)
    do {
      (_, response) = try await URLSession.shared.data(for: request)
    } catch {
      throw .transportFailure(underlying: error as! (any Error & Sendable))
    }

    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      if http.statusCode == 429 {
        throw .rateLimited(retryAfter: nil)
      }
      throw .serverError(code: http.statusCode, message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
    }
  }
}

public struct HttpBroadcastMessage: Sendable {
  public let topic: String
  public let event: String
  public let payload: any Encodable & Sendable
  public let isPrivate: Bool

  public init(topic: String, event: String, payload: any Encodable & Sendable, isPrivate: Bool = false) {
    self.topic = topic; self.event = event; self.payload = payload; self.isPrivate = isPrivate
  }
}
```

- [ ] **Step 6: Run broadcast tests**

```bash
cd Packages/_Realtime && swift test --filter BroadcastTests
```

Expected: All 3 tests pass.

- [ ] **Step 7: Commit**

```bash
git add Packages/_Realtime/Sources/_Realtime/Broadcast \
        Packages/_Realtime/Tests/_RealtimeTests/BroadcastTests.swift
git commit -m "feat(_Realtime): Phase 5 — broadcast streams + HTTP one-shot send"
```

---

## Task 2: Presence (Phase 6)

**Files:**
- Create: `Packages/_Realtime/Sources/_Realtime/Presence/PresenceHandle.swift`
- Create: `Packages/_Realtime/Sources/_Realtime/Presence/PresenceState.swift`
- Create: `Packages/_Realtime/Sources/_Realtime/Presence/Presence.swift`
- Create: `Packages/_Realtime/Sources/_Realtime/Presence/Channel+Presence.swift`
- Create: `Packages/_Realtime/Tests/_RealtimeTests/PresenceTests.swift`

- [ ] **Step 1: Write failing presence tests**

```swift
import Testing
import IssueReporting
@testable import _Realtime

@Suite struct PresenceTests {
  static let testURL = URL(string: "ws://localhost:4000/realtime/v1")!

  func makeConnectedChannel(topic: String = "room:1") async throws -> (Channel, InMemoryServer) {
    let (transport, server) = InMemoryTransport.pair()
    let realtime = Realtime(url: Self.testURL, apiKey: .literal("key"), transport: transport)
    try await realtime.connect()
    Task {
      for await frame in server.receivedFrames {
        guard let text = frame.text, let msg = try? PhoenixSerializer.decodeText(text) else { continue }
        if msg.event == "phx_join" || msg.event == "presence" {
          let reply = PhoenixMessage(joinRef: msg.joinRef, ref: msg.ref, topic: msg.topic, event: "phx_reply", payload: ["status": "ok", "response": .object([:])])
          await server.send(.text(try! PhoenixSerializer.encodeText(reply)))
        }
      }
    }
    return (realtime.channel(topic), server)
  }

  @Test func trackSendsPresenceEvent() async throws {
    struct State: Codable, Sendable { let userId: String }
    let (channel, server) = try await makeConnectedChannel()
    try await channel.join()

    let handle = try await channel.presence.track(State(userId: "u1"))
    #expect(handle != nil)

    // Server receives a presence push
    let frame = await server.receive()
    #expect(frame?.text?.contains("presence") == true)
    try await handle.cancel()
  }

  @Test func observeDeliversPresenceSnapshot() async throws {
    struct UserState: Decodable, Sendable { let name: String }
    let (channel, server) = try await makeConnectedChannel()
    try await channel.join()

    let states = await channel.presence.observe(UserState.self)
    var snapshots: [PresenceState<UserState>] = []
    Task { for await s in states { snapshots.append(s) } }

    // Server pushes presence_state
    let presenceMsg = PhoenixMessage(
      joinRef: nil, ref: nil, topic: "room:1", event: "presence_state",
      payload: ["alice": .object(["metas": .array([.object(["name": "Alice"])])])]
    )
    await server.send(.text(try! PhoenixSerializer.encodeText(presenceMsg)))

    try await Task.sleep(for: .milliseconds(50))
    #expect(!snapshots.isEmpty)
  }
}
```

- [ ] **Step 2: Run — expect compile failure**

```bash
cd Packages/_Realtime && swift test --filter PresenceTests 2>&1 | head -10
```

- [ ] **Step 3: Create `Presence/PresenceState.swift`**

```swift
import Foundation

public typealias PresenceKey = String

public struct PresenceState<T: Sendable>: Sendable {
  /// All currently tracked presences keyed by presence key; each key may have multiple metas.
  public let active: [PresenceKey: [T]]
  /// The diff that produced this snapshot (nil on first emission).
  public let lastDiff: PresenceDiff<T>?
}

public struct PresenceDiff<T: Sendable>: Sendable {
  public let joined: [(PresenceKey, T)]
  public let left: [(PresenceKey, T)]
}
```

- [ ] **Step 4: Create `Presence/PresenceHandle.swift`**

```swift
import Foundation
import IssueReporting

public final class PresenceHandle: Sendable {
  private let _cancel: @Sendable () async throws(RealtimeError) -> Void
  private let id: UUID = UUID()
  private let isCancelled = _Atomic(false)

  init(cancel: @escaping @Sendable () async throws(RealtimeError) -> Void) {
    self._cancel = cancel
  }

  deinit {
    if !isCancelled.value {
      reportIssue("PresenceHandle deinited without cancel() — presence was not untracked. Call cancel() when done.")
    }
  }

  /// Idempotent. Untracks this presence meta. Awaits server ACK.
  public func cancel() async throws(RealtimeError) {
    guard !isCancelled.exchange(true) else { return }
    try await _cancel()
  }
}

/// Thread-safe boolean for use in non-isolated contexts.
private final class _Atomic<T: Sendable>: @unchecked Sendable {
  private var _value: T
  private let lock = NSLock()
  init(_ value: T) { _value = value }
  var value: T { lock.withLock { _value } }
  @discardableResult func exchange(_ newValue: T) -> T {
    lock.withLock { let old = _value; _value = newValue; return old }
  }
}
```

- [ ] **Step 5: Create `Presence/Presence.swift`**

```swift
import Foundation

public struct Presence: Sendable {
  private let channel: Channel

  init(channel: Channel) { self.channel = channel }

  /// Begin tracking state for this client. Returns a handle; call `handle.cancel()` to untrack.
  public func track<T: Codable & Sendable>(_ state: T) async throws(RealtimeError) -> PresenceHandle {
    guard let realtime = await channel.realtime else { throw .disconnected }
    let data: Data
    do { data = try await realtime.configuration.encoder.encode(state) }
    catch { throw .encoding(underlying: error as! (any Error & Sendable)) }
    guard let obj = try? JSONDecoder().decode([String: JSONValue].self, from: data) else {
      throw .encoding(underlying: EncodingError.invalidValue(state, .init(codingPath: [], debugDescription: "Not a JSON object")))
    }
    let topic = await channel.topic
    let joinRef = await channel.joinRef
    let trackMsg = PhoenixMessage(
      joinRef: joinRef, ref: nil,
      topic: topic, event: "presence",
      payload: ["event": "track", "payload": .object(obj)]
    )
    _ = try await realtime.sendAndAwait(trackMsg, timeout: realtime.configuration.joinTimeout)

    // Store state for auto re-track on reconnect
    let trackId = UUID()
    await channel.registerTrack(id: trackId, state: obj)

    return PresenceHandle {
      await channel.unregisterTrack(id: trackId)
      let untrackMsg = PhoenixMessage(
        joinRef: joinRef, ref: nil,
        topic: topic, event: "presence",
        payload: ["event": "untrack"]
      )
      _ = try await realtime.sendAndAwait(untrackMsg, timeout: realtime.configuration.joinTimeout)
    }
  }

  /// Snapshot + diff stream of all presences in the channel.
  public func observe<T: Decodable & Sendable>(_ type: T.Type = T.self) -> AsyncStream<PresenceState<T>> {
    AsyncStream { continuation in
      let id = UUID()
      Task {
        await channel.registerPresenceContinuation(id: id, onSnapshot: { raw in
          let state = decodePresenceState(raw, as: T.self)
          continuation.yield(state)
        })
        continuation.onTermination = { [id] _ in
          Task { await channel.unregisterPresenceContinuation(id: id) }
        }
        do { try await channel.joinIfNeeded() }
        catch { continuation.finish() }
      }
    }
  }

  /// Incremental diffs only.
  public func diffs<T: Decodable & Sendable>(_ type: T.Type = T.self) -> AsyncStream<PresenceDiff<T>> {
    AsyncStream { continuation in
      let id = UUID()
      Task {
        await channel.registerPresenceDiffContinuation(id: id, onDiff: { raw in
          let diff = decodePresenceDiff(raw, as: T.self)
          continuation.yield(diff)
        })
        continuation.onTermination = { [id] _ in
          Task { await channel.unregisterPresenceDiffContinuation(id: id) }
        }
        do { try await channel.joinIfNeeded() }
        catch { continuation.finish() }
      }
    }
  }
}

// MARK: - Decoding helpers

private func decodePresenceState<T: Decodable>(_ raw: [String: JSONValue], as type: T.Type) -> PresenceState<T> {
  var active: [PresenceKey: [T]] = [:]
  for (key, val) in raw {
    guard case .object(let entry) = val,
          case .array(let metas) = entry["metas"] else { continue }
    active[key] = metas.compactMap { metaVal -> T? in
      guard case .object(let metaObj) = metaVal,
            let data = try? JSONEncoder().encode(metaObj),
            let decoded = try? JSONDecoder().decode(T.self, from: data) else { return nil }
      return decoded
    }
  }
  return PresenceState(active: active, lastDiff: nil)
}

private func decodePresenceDiff<T: Decodable>(_ raw: [String: JSONValue], as type: T.Type) -> PresenceDiff<T> {
  func extractEntries(_ val: JSONValue?) -> [(PresenceKey, T)] {
    guard case .object(let dict) = val else { return [] }
    return dict.flatMap { key, entry -> [(PresenceKey, T)] in
      guard case .object(let entryObj) = entry,
            case .array(let metas) = entryObj["metas"] else { return [] }
      return metas.compactMap { metaVal -> (PresenceKey, T)? in
        guard case .object(let metaObj) = metaVal,
              let data = try? JSONEncoder().encode(metaObj),
              let decoded = try? JSONDecoder().decode(T.self, from: data) else { return nil }
        return (key, decoded)
      }
    }
  }
  return PresenceDiff(joined: extractEntries(raw["joins"]), left: extractEntries(raw["leaves"]))
}
```

- [ ] **Step 6: Create `Presence/Channel+Presence.swift`**

```swift
import Foundation

extension Channel {
  public var presence: Presence { Presence(channel: self) }

  // Track registry for auto re-track on reconnect
  private(set) var trackedStates: [UUID: [String: JSONValue]] = [:]
  typealias PresenceSnapshotHandler = @Sendable ([String: JSONValue]) -> Void
  typealias PresenceDiffHandler = @Sendable ([String: JSONValue]) -> Void
  var presenceSnapshotHandlers: [UUID: PresenceSnapshotHandler] = [:]
  var presenceDiffHandlers: [UUID: PresenceDiffHandler] = [:]

  func registerTrack(id: UUID, state: [String: JSONValue]) {
    trackedStates[id] = state
  }

  func unregisterTrack(id: UUID) {
    trackedStates.removeValue(forKey: id)
  }

  func registerPresenceContinuation(id: UUID, onSnapshot: @escaping PresenceSnapshotHandler) {
    presenceSnapshotHandlers[id] = onSnapshot
  }

  func unregisterPresenceContinuation(id: UUID) {
    presenceSnapshotHandlers.removeValue(forKey: id)
  }

  func registerPresenceDiffContinuation(id: UUID, onDiff: @escaping PresenceDiffHandler) {
    presenceDiffHandlers[id] = onDiff
  }

  func unregisterPresenceDiffContinuation(id: UUID) {
    presenceDiffHandlers.removeValue(forKey: id)
  }

  func joinIfNeeded() async throws(RealtimeError) {
    if currentState == .unsubscribed { try await join() }
  }
}
```

Update `Channel.handle(_:)` in `Channel.swift` to route presence events:

```swift
case "presence_state":
  for handler in presenceSnapshotHandlers.values { handler(msg.payload) }
case "presence_diff":
  for handler in presenceDiffHandlers.values { handler(msg.payload) }
```

- [ ] **Step 7: Run presence tests**

```bash
cd Packages/_Realtime && swift test --filter PresenceTests
```

Expected: All 2 tests pass.

- [ ] **Step 8: Commit**

```bash
git add Packages/_Realtime/Sources/_Realtime/Presence \
        Packages/_Realtime/Tests/_RealtimeTests/PresenceTests.swift
git commit -m "feat(_Realtime): Phase 6 — presence track/observe/diffs with auto re-track"
```

---

## Task 3: Postgres Changes (Phase 7)

**Files:**
- Create: `Packages/_Realtime/Sources/_Realtime/Postgres/RealtimeTable.swift`
- Create: `Packages/_Realtime/Sources/_Realtime/Postgres/Filter.swift`
- Create: `Packages/_Realtime/Sources/_Realtime/Postgres/PostgresChange.swift`
- Create: `Packages/_Realtime/Sources/_Realtime/Postgres/Channel+Postgres.swift`
- Create: `Packages/_Realtime/Tests/_RealtimeTests/PostgresChangesTests.swift`

- [ ] **Step 1: Write failing postgres tests**

```swift
import Testing
@testable import _Realtime

@Suite struct PostgresChangesTests {

  @Test func filterEqEncodesCorrectly() {
    struct User: RealtimeTable {
      static let schema = "public"
      static let tableName = "users"
      static func columnName<V>(for kp: KeyPath<User, V>) -> String {
        switch kp {
        case \Self.id:   return "id"
        case \Self.name: return "name"
        default: return ""
        }
      }
      var id: UUID
      var name: String
    }
    let filter = Filter.eq(\User.id, UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    #expect(filter.wireValue == "id=eq.00000000-0000-0000-0000-000000000001")
  }

  @Test func filterInEncodesCorrectly() {
    struct Item: RealtimeTable {
      static let schema = "public"
      static let tableName = "items"
      static func columnName<V>(for kp: KeyPath<Item, V>) -> String { "status" }
      var status: String
    }
    let filter = Filter.in(\Item.status, ["active", "pending"])
    #expect(filter.wireValue == "status=in.(active,pending)")
  }

  @Test func untypedFilterEncodesCorrectly() {
    let filter = UntypedFilter.eq("room_id", "abc-123")
    #expect(filter.wireValue == "room_id=eq.abc-123")
  }

  @Test func postgresChangeDecodesInsert() throws {
    struct Message: Codable, Sendable {
      let id: Int
      let text: String
    }

    let payload: [String: JSONValue] = [
      "data": .object([
        "type": "INSERT",
        "record": .object(["id": .int(1), "text": .string("hello")]),
        "old_record": .null,
        "columns": .array([]),
        "commit_timestamp": .string("2026-01-01T00:00:00Z"),
      ]),
      "ids": .array([.int(1)])
    ]

    let change = try PostgresChange<Message>.decode(from: payload)
    if case .insert(let row) = change {
      #expect(row.id == 1)
      #expect(row.text == "hello")
    } else {
      Issue.record("Expected .insert, got \(change)")
    }
  }
}
```

- [ ] **Step 2: Run — expect compile failure**

```bash
cd Packages/_Realtime && swift test --filter PostgresChangesTests 2>&1 | head -10
```

- [ ] **Step 3: Create `Postgres/RealtimeTable.swift`**

```swift
/// Conform your table model to `RealtimeTable` to use typed `Filter<T>` in postgres change streams.
///
/// When you own the type, use the `@RealtimeTable` macro (Phase 8) to synthesize this conformance.
/// For types you don't own, write the conformance manually:
/// ```swift
/// extension ExternalType: RealtimeTable {
///   static let schema = "public"
///   static let tableName = "widgets"
///   static func columnName<V>(for kp: KeyPath<Self, V>) -> String {
///     switch kp {
///     case \Self.id: return "id"
///     default: fatalError("Unknown key path")
///     }
///   }
/// }
/// ```
public protocol RealtimeTable {
  static var schema: String { get }
  static var tableName: String { get }
  static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String
}

/// Value types usable in filter predicates.
public protocol RealtimeFilterValue {
  var filterString: String { get }
}

extension String: RealtimeFilterValue { public var filterString: String { self } }
extension Int:    RealtimeFilterValue { public var filterString: String { String(self) } }
extension Double: RealtimeFilterValue { public var filterString: String { String(self) } }
extension Bool:   RealtimeFilterValue { public var filterString: String { String(self) } }
extension UUID:   RealtimeFilterValue { public var filterString: String { uuidString.lowercased() } }
```

- [ ] **Step 4: Create `Postgres/Filter.swift`**

```swift
/// Typed filter for postgres_changes subscriptions. One clause per subscription (wire constraint).
///
/// Use static factories with `KeyPath<T, V>` — the value type is compile-time checked:
/// ```swift
/// .eq(\Message.roomId, roomId)   // roomId: UUID — correct
/// .eq(\Message.roomId, 42)       // compile error — Int != UUID
/// ```
public struct Filter<T: RealtimeTable>: Sendable {
  let wireValue: String

  public static func eq<V: RealtimeFilterValue>(_ kp: KeyPath<T, V>, _ v: V) -> Filter<T> {
    Filter(wireValue: "\(T.columnName(for: kp))=eq.\(v.filterString)")
  }
  public static func neq<V: RealtimeFilterValue>(_ kp: KeyPath<T, V>, _ v: V) -> Filter<T> {
    Filter(wireValue: "\(T.columnName(for: kp))=neq.\(v.filterString)")
  }
  public static func gt<V: RealtimeFilterValue>(_ kp: KeyPath<T, V>, _ v: V) -> Filter<T> {
    Filter(wireValue: "\(T.columnName(for: kp))=gt.\(v.filterString)")
  }
  public static func gte<V: RealtimeFilterValue>(_ kp: KeyPath<T, V>, _ v: V) -> Filter<T> {
    Filter(wireValue: "\(T.columnName(for: kp))=gte.\(v.filterString)")
  }
  public static func lt<V: RealtimeFilterValue>(_ kp: KeyPath<T, V>, _ v: V) -> Filter<T> {
    Filter(wireValue: "\(T.columnName(for: kp))=lt.\(v.filterString)")
  }
  public static func lte<V: RealtimeFilterValue>(_ kp: KeyPath<T, V>, _ v: V) -> Filter<T> {
    Filter(wireValue: "\(T.columnName(for: kp))=lte.\(v.filterString)")
  }
  public static func `in`<V: RealtimeFilterValue>(_ kp: KeyPath<T, V>, _ values: [V]) -> Filter<T> {
    let list = values.map(\.filterString).joined(separator: ",")
    return Filter(wireValue: "\(T.columnName(for: kp))=in.(\(list))")
  }
}

/// Untyped filter for types that don't conform to `RealtimeTable`.
public struct UntypedFilter: Sendable {
  let wireValue: String
  let column: String

  public static func eq(_ column: String, _ value: any RealtimeFilterValue) -> UntypedFilter {
    UntypedFilter(wireValue: "\(column)=eq.\(value.filterString)", column: column)
  }
  public static func neq(_ column: String, _ value: any RealtimeFilterValue) -> UntypedFilter {
    UntypedFilter(wireValue: "\(column)=neq.\(value.filterString)", column: column)
  }
  public static func gt(_ column: String, _ value: any RealtimeFilterValue) -> UntypedFilter {
    UntypedFilter(wireValue: "\(column)=gt.\(value.filterString)", column: column)
  }
  public static func gte(_ column: String, _ value: any RealtimeFilterValue) -> UntypedFilter {
    UntypedFilter(wireValue: "\(column)=gte.\(value.filterString)", column: column)
  }
  public static func lt(_ column: String, _ value: any RealtimeFilterValue) -> UntypedFilter {
    UntypedFilter(wireValue: "\(column)=lt.\(value.filterString)", column: column)
  }
  public static func lte(_ column: String, _ value: any RealtimeFilterValue) -> UntypedFilter {
    UntypedFilter(wireValue: "\(column)=lte.\(value.filterString)", column: column)
  }
  public static func `in`(_ column: String, _ values: [any RealtimeFilterValue]) -> UntypedFilter {
    let list = values.map(\.filterString).joined(separator: ",")
    return UntypedFilter(wireValue: "\(column)=in.(\(list))", column: column)
  }
}
```

- [ ] **Step 5: Create `Postgres/PostgresChange.swift`**

```swift
import Foundation

/// A decoded postgres_changes event.
public enum PostgresChange<T: Sendable>: Sendable {
  case insert(T)
  case update(old: T, new: T)
  case delete(old: T)

  static func decode(from payload: [String: JSONValue]) throws -> PostgresChange<T>
    where T: Decodable
  {
    guard case .object(let data) = payload["data"] else {
      throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Missing 'data' key"))
    }
    guard case .string(let type) = data["type"] else {
      throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Missing 'type'"))
    }

    func decodeRecord(_ key: String) throws -> T {
      guard case .object(let obj) = data[key] else {
        throw DecodingError.keyNotFound(
          CodingUserInfoKey(rawValue: key)!,
          .init(codingPath: [], debugDescription: "Missing '\(key)'")
        )
      }
      let recordData = try JSONEncoder().encode(obj)
      return try JSONDecoder().decode(T.self, from: recordData)
    }

    switch type {
    case "INSERT":
      return .insert(try decodeRecord("record"))
    case "UPDATE":
      return .update(old: try decodeRecord("old_record"), new: try decodeRecord("record"))
    case "DELETE":
      return .delete(old: try decodeRecord("old_record"))
    default:
      throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unknown type: \(type)"))
    }
  }
}
```

- [ ] **Step 6: Create `Postgres/Channel+Postgres.swift`**

```swift
import Foundation

extension Channel {
  // MARK: Typed streams

  public func changes<T: Decodable & Sendable & RealtimeTable>(
    to type: T.Type = T.self,
    where filter: Filter<T>? = nil,
    decoder: JSONDecoder? = nil
  ) -> AsyncThrowingStream<PostgresChange<T>, RealtimeError> {
    let subscriptionId = UUID()
    let dec = decoder ?? JSONDecoder()
    return AsyncThrowingStream { continuation in
      let id = UUID()
      Task {
        await registerPostgresContinuation(id: id) { payload in
          do {
            let change = try PostgresChange<T>.decode(from: payload)
            continuation.yield(change)
          } catch {
            continuation.finish(throwing: .decoding(type: String(describing: T.self), underlying: error as! (any Error & Sendable)))
          }
        }
        continuation.onTermination = { [id] _ in
          Task { await self.unregisterPostgresContinuation(id: id) }
        }
        do { try await joinWithPostgresFilter(
          schema: T.schema, table: T.tableName,
          filter: filter?.wireValue,
          subscriptionId: subscriptionId
        ) }
        catch let e as RealtimeError { continuation.finish(throwing: e) }
      }
    }
  }

  public func inserts<T: Decodable & Sendable & RealtimeTable>(
    into type: T.Type = T.self,
    where filter: Filter<T>? = nil
  ) -> AsyncThrowingStream<T, RealtimeError> {
    let raw = changes(to: T.self, where: filter)
    return AsyncThrowingStream { continuation in
      Task {
        do {
          for try await change in raw {
            if case .insert(let row) = change { continuation.yield(row) }
          }
          continuation.finish()
        } catch let e as RealtimeError { continuation.finish(throwing: e) }
      }
    }
  }

  public func updates<T: Decodable & Sendable & RealtimeTable>(
    of type: T.Type = T.self,
    where filter: Filter<T>? = nil
  ) -> AsyncThrowingStream<(old: T, new: T), RealtimeError> {
    let raw = changes(to: T.self, where: filter)
    return AsyncThrowingStream { continuation in
      Task {
        do {
          for try await change in raw {
            if case .update(let old, let new) = change { continuation.yield((old, new)) }
          }
          continuation.finish()
        } catch let e as RealtimeError { continuation.finish(throwing: e) }
      }
    }
  }

  public func deletes<T: Decodable & Sendable & RealtimeTable>(
    from type: T.Type = T.self,
    where filter: Filter<T>? = nil
  ) -> AsyncThrowingStream<T, RealtimeError> {
    let raw = changes(to: T.self, where: filter)
    return AsyncThrowingStream { continuation in
      Task {
        do {
          for try await change in raw {
            if case .delete(let old) = change { continuation.yield(old) }
          }
          continuation.finish()
        } catch let e as RealtimeError { continuation.finish(throwing: e) }
      }
    }
  }

  // MARK: Untyped escape hatch

  public func changes(
    schema: String = "public",
    table: String,
    filter: UntypedFilter? = nil,
    decoder: JSONDecoder? = nil
  ) -> AsyncThrowingStream<PostgresChange<[String: JSONValue]>, RealtimeError> {
    let subscriptionId = UUID()
    return AsyncThrowingStream { continuation in
      let id = UUID()
      Task {
        await registerPostgresContinuation(id: id) { payload in
          do {
            let change = try PostgresChange<[String: JSONValue]>.decode(from: payload)
            continuation.yield(change)
          } catch {
            continuation.finish(throwing: .decoding(type: "JSONValue", underlying: error as! (any Error & Sendable)))
          }
        }
        continuation.onTermination = { [id] _ in
          Task { await self.unregisterPostgresContinuation(id: id) }
        }
        do { try await joinWithPostgresFilter(
          schema: schema, table: table,
          filter: filter?.wireValue,
          subscriptionId: subscriptionId
        ) }
        catch let e as RealtimeError { continuation.finish(throwing: e) }
      }
    }
  }

  // MARK: - Internal registration

  typealias PostgresHandler = @Sendable ([String: JSONValue]) -> Void
  var postgresHandlers: [UUID: PostgresHandler] = [:]

  func registerPostgresContinuation(id: UUID, handler: @escaping PostgresHandler) {
    postgresHandlers[id] = handler
  }

  func unregisterPostgresContinuation(id: UUID) {
    postgresHandlers.removeValue(forKey: id)
  }

  // Delivers a postgres_changes payload to all handlers
  func deliverPostgresChange(_ payload: [String: JSONValue]) {
    for handler in postgresHandlers.values { handler(payload) }
  }

  // Includes postgres_changes config in the join payload
  private func joinWithPostgresFilter(
    schema: String, table: String,
    filter: String?, subscriptionId: UUID
  ) async throws(RealtimeError) {
    // Store subscription so it's re-sent on rejoin
    await addPostgresSubscription(PostgresSubscription(
      id: subscriptionId, schema: schema, table: table, filter: filter
    ))
    if currentState == .unsubscribed { try await join() }
  }
}

// MARK: - Postgres subscription registry (stored on Channel)
struct PostgresSubscription: Sendable {
  let id: UUID
  let schema: String
  let table: String
  let filter: String?
}

extension Channel {
  var postgresSubscriptions: [UUID: PostgresSubscription] {
    get { _postgresSubscriptions }
    set { _postgresSubscriptions = newValue }
  }
  // Backing storage — Swift actor stored properties can't use lazy/computed in extensions
  // Store in a wrapper on the actor
  func addPostgresSubscription(_ sub: PostgresSubscription) {
    _postgresSubscriptions[sub.id] = sub
  }
}
```

Note: `_postgresSubscriptions` needs to be a stored property on `Channel`. Add to `Channel.swift`:

```swift
// Inside Channel actor body (add to stored properties):
var _postgresSubscriptions: [UUID: PostgresSubscription] = [:]
```

And update `buildJoinPayload()` in `Channel.swift` to include postgres_changes:

```swift
let changes: [JSONValue] = _postgresSubscriptions.values.map { sub in
  var entry: [String: JSONValue] = [
    "event": "*",
    "schema": .string(sub.schema),
    "table": .string(sub.table),
  ]
  if let f = sub.filter { entry["filter"] = .string(f) }
  return .object(entry)
}
if !changes.isEmpty {
  config["postgres_changes"] = .array(changes)
}
```

Update `Channel.handle(_:)` to deliver postgres changes:

```swift
case "postgres_changes":
  deliverPostgresChange(msg.payload)
```

- [ ] **Step 7: Run postgres tests**

```bash
cd Packages/_Realtime && swift test --filter PostgresChangesTests
```

Expected: All 4 tests pass.

- [ ] **Step 8: Run full test suite**

```bash
cd Packages/_Realtime && swift test
```

Expected: All tests pass, 0 failures.

- [ ] **Step 9: Commit**

```bash
git add Packages/_Realtime/Sources/_Realtime/Postgres \
        Packages/_Realtime/Tests/_RealtimeTests/PostgresChangesTests.swift
git commit -m "feat(_Realtime): Phase 7 — Postgres changes with typed Filter<T> and untyped escape hatch"
```
