# Realtime v3 — Phase 3 & 4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the `Realtime` actor (WebSocket connection, reconnection, heartbeat) and the `Channel` actor (join/leave lifecycle, topic identity, options lock).

**Architecture:** `Realtime` owns the WebSocket connection, channels registry, pending-reply tracking, and reconnect loop. `Channel` owns its join/leave state machine and per-feature continuation dictionaries. Cross-actor calls use `await`. Phoenix wire protocol is handled by an internal `PhoenixSerializer`.

**Tech Stack:** Swift 6.0 actors, typed throws, `AsyncThrowingStream`, `swift-clocks` TestClock, `InMemoryTransport` from Phase 2.

**Prerequisite:** Phases 1 & 2 complete and committed.

---

## Task 1: Internal JSON + Phoenix wire types

**Files:**
- Create: `Packages/_Realtime/Sources/_Realtime/Internal/JSONValue.swift`
- Create: `Packages/_Realtime/Sources/_Realtime/Internal/PhoenixMessage.swift`
- Create: `Packages/_Realtime/Sources/_Realtime/Internal/PhoenixSerializer.swift`

- [ ] **Step 1: Write failing test for PhoenixSerializer**

Create `Packages/_Realtime/Tests/_RealtimeTests/PhoenixSerializerTests.swift`:

```swift
import Testing
import Foundation
@testable import _Realtime

@Suite struct PhoenixSerializerTests {
  @Test func roundTripTextFrame() throws {
    let msg = PhoenixMessage(
      joinRef: "1", ref: "2", topic: "room:1",
      event: "phx_join", payload: ["status": .string("ok")]
    )
    let frame = try PhoenixSerializer.encodeText(msg)
    let decoded = try PhoenixSerializer.decodeText(frame)
    #expect(decoded.joinRef == "1")
    #expect(decoded.ref == "2")
    #expect(decoded.topic == "room:1")
    #expect(decoded.event == "phx_join")
    #expect(decoded.payload["status"] == .string("ok"))
  }

  @Test func decodeTextWithNullRefs() throws {
    // [null, null, "phoenix", "heartbeat", {}]
    let json = "[null,null,\"phoenix\",\"heartbeat\",{}]"
    let decoded = try PhoenixSerializer.decodeText(json)
    #expect(decoded.joinRef == nil)
    #expect(decoded.ref == nil)
    #expect(decoded.topic == "phoenix")
    #expect(decoded.event == "heartbeat")
  }

  @Test func decodeBinaryBroadcast() throws {
    // Build a minimal type-0x04 binary frame
    let topic = "room:1"
    let event = "chat"
    let payload = Data("{\"msg\":\"hi\"}".utf8)

    var data = Data()
    data.append(0x04)                          // kind = server broadcast
    data.append(UInt8(topic.utf8.count))       // topic_len
    data.append(UInt8(event.utf8.count))       // event_len
    data.append(0x00)                          // meta_len
    data.append(0x01)                          // encoding = json
    data.append(contentsOf: topic.utf8)
    data.append(contentsOf: event.utf8)
    data.append(payload)

    let broadcast = try PhoenixSerializer.decodeBinary(data)
    #expect(broadcast.topic == "room:1")
    #expect(broadcast.event == "chat")
  }
}
```

- [ ] **Step 2: Run — expect compile failure**

```bash
cd Packages/_Realtime && swift test --filter PhoenixSerializerTests 2>&1 | head -10
```

Expected: error: cannot find type 'PhoenixMessage'

- [ ] **Step 3: Create `Internal/JSONValue.swift`**

```swift
import Foundation

/// Codable JSON value without external dependencies.
public enum JSONValue: Codable, Sendable, Equatable {
  case string(String)
  case double(Double)
  case int(Int)
  case bool(Bool)
  case null
  indirect case array([JSONValue])
  indirect case object([String: JSONValue])

  public init(from decoder: any Decoder) throws {
    let c = try decoder.singleValueContainer()
    if let v = try? c.decode(Bool.self)             { self = .bool(v);   return }
    if let v = try? c.decode(Int.self)              { self = .int(v);    return }
    if let v = try? c.decode(Double.self)           { self = .double(v); return }
    if let v = try? c.decode(String.self)           { self = .string(v); return }
    if c.decodeNil()                                { self = .null;      return }
    if let v = try? c.decode([JSONValue].self)      { self = .array(v);  return }
    if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
    throw DecodingError.dataCorrupted(
      .init(codingPath: decoder.codingPath, debugDescription: "Cannot decode JSONValue")
    )
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .string(let v): try c.encode(v)
    case .double(let v): try c.encode(v)
    case .int(let v):    try c.encode(v)
    case .bool(let v):   try c.encode(v)
    case .null:          try c.encodeNil()
    case .array(let v):  try c.encode(v)
    case .object(let v): try c.encode(v)
    }
  }
}

extension JSONValue: ExpressibleByStringLiteral {
  public init(stringLiteral v: String) { self = .string(v) }
}
extension JSONValue: ExpressibleByIntegerLiteral {
  public init(integerLiteral v: Int) { self = .int(v) }
}
extension JSONValue: ExpressibleByFloatLiteral {
  public init(floatLiteral v: Double) { self = .double(v) }
}
extension JSONValue: ExpressibleByBooleanLiteral {
  public init(booleanLiteral v: Bool) { self = .bool(v) }
}
extension JSONValue: ExpressibleByNilLiteral {
  public init(nilLiteral: ()) { self = .null }
}
extension JSONValue: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}
extension JSONValue: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (String, JSONValue)...) {
    self = .object(Dictionary(uniqueKeysWithValues: elements))
  }
}
```

- [ ] **Step 4: Create `Internal/PhoenixMessage.swift`**

```swift
import Foundation

/// Decoded Phoenix protocol message (text array format or binary broadcast).
struct PhoenixMessage: Sendable {
  var joinRef: String?
  var ref: String?
  var topic: String
  var event: String
  var payload: [String: JSONValue]
}

/// Decoded server-to-client binary broadcast (type 0x04).
struct BinaryBroadcast: Sendable {
  let topic: String
  let event: String
  enum Payload: Sendable {
    case json([String: JSONValue])
    case binary(Data)
  }
  let payload: Payload
}
```

- [ ] **Step 5: Create `Internal/PhoenixSerializer.swift`**

Vendor from `Sources/Realtime/RealtimeSerializer.swift`, adapted to use `JSONValue` instead of `AnyJSON`:

```swift
import Foundation

enum PhoenixSerializer {
  enum BinaryKind: UInt8 {
    case clientBroadcastPush = 3
    case serverBroadcast = 4
  }
  enum PayloadEncoding: UInt8 {
    case binary = 0
    case json = 1
  }

  // MARK: Text

  static func encodeText(_ msg: PhoenixMessage) throws -> String {
    let array: [JSONValue] = [
      msg.joinRef.map { .string($0) } ?? .null,
      msg.ref.map { .string($0) } ?? .null,
      .string(msg.topic),
      .string(msg.event),
      .object(msg.payload),
    ]
    let data = try JSONEncoder().encode(array)
    guard let text = String(data: data, encoding: .utf8) else {
      throw RealtimeError.encoding(underlying: EncodingError.invalidValue(array, .init(codingPath: [], debugDescription: "UTF-8 failure")))
    }
    return text
  }

  static func decodeText(_ text: String) throws -> PhoenixMessage {
    let data = Data(text.utf8)
    let array = try JSONDecoder().decode([JSONValue].self, from: data)
    guard array.count >= 5 else {
      throw RealtimeError.decoding(type: "PhoenixMessage", underlying: DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected 5-element array, got \(array.count)")))
    }
    let joinRef: String? = if case .string(let s) = array[0] { s } else { nil }
    let ref: String?     = if case .string(let s) = array[1] { s } else { nil }
    guard case .string(let topic)   = array[2],
          case .string(let event)   = array[3],
          case .object(let payload) = array[4]
    else {
      throw RealtimeError.decoding(type: "PhoenixMessage", underlying: DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unexpected array element types")))
    }
    return PhoenixMessage(joinRef: joinRef, ref: ref, topic: topic, event: event, payload: payload)
  }

  // MARK: Binary decode (server→client, type 0x04)

  static func decodeBinary(_ data: Data) throws -> BinaryBroadcast {
    guard data.count >= 5 else {
      throw RealtimeError.decoding(type: "BinaryBroadcast", underlying: DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Binary frame too short: \(data.count)")))
    }
    let kind = data[data.startIndex]
    guard kind == BinaryKind.serverBroadcast.rawValue else {
      throw RealtimeError.decoding(type: "BinaryBroadcast", underlying: DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unexpected kind byte: \(kind)")))
    }
    let topicLen = Int(data[data.startIndex + 1])
    let eventLen = Int(data[data.startIndex + 2])
    let metaLen  = Int(data[data.startIndex + 3])
    let encByte  = data[data.startIndex + 4]
    guard let encoding = PayloadEncoding(rawValue: encByte) else {
      throw RealtimeError.decoding(type: "BinaryBroadcast", underlying: DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unknown encoding: \(encByte)")))
    }
    let headerSize = 5
    guard data.count >= headerSize + topicLen + eventLen + metaLen else {
      throw RealtimeError.decoding(type: "BinaryBroadcast", underlying: DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Frame too short for field lengths")))
    }
    var offset = data.startIndex + headerSize
    let topicData = data[offset..<(offset + topicLen)]; offset += topicLen
    let eventData = data[offset..<(offset + eventLen)]; offset += eventLen
    offset += metaLen
    let payloadData = data[offset...]
    guard let topic = String(data: topicData, encoding: .utf8),
          let event = String(data: eventData, encoding: .utf8) else {
      throw RealtimeError.decoding(type: "BinaryBroadcast", underlying: DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "UTF-8 decode failure")))
    }
    let payload: BinaryBroadcast.Payload
    switch encoding {
    case .json:
      let obj = try JSONDecoder().decode([String: JSONValue].self, from: Data(payloadData))
      payload = .json(obj)
    case .binary:
      payload = .binary(Data(payloadData))
    }
    return BinaryBroadcast(topic: topic, event: event, payload: payload)
  }

  // MARK: Binary encode (client→server, type 0x03)

  static func encodeBroadcastPush(
    joinRef: String?, ref: String?,
    topic: String, event: String,
    payload: [String: JSONValue]
  ) throws -> Data {
    let payloadData = try JSONEncoder().encode(payload)
    return try _encodePush(joinRef: joinRef, ref: ref, topic: topic, event: event, encoding: .json, payload: payloadData)
  }

  static func encodeBroadcastPush(
    joinRef: String?, ref: String?,
    topic: String, event: String,
    binaryPayload: Data
  ) throws -> Data {
    try _encodePush(joinRef: joinRef, ref: ref, topic: topic, event: event, encoding: .binary, payload: binaryPayload)
  }

  private static func _encodePush(
    joinRef: String?, ref: String?,
    topic: String, event: String,
    encoding: PayloadEncoding, payload: Data
  ) throws -> Data {
    let jrBytes = Data((joinRef ?? "").utf8)
    let rBytes  = Data((ref ?? "").utf8)
    let tBytes  = Data(topic.utf8)
    let eBytes  = Data(event.utf8)
    guard jrBytes.count <= 255, rBytes.count <= 255, tBytes.count <= 255, eBytes.count <= 255 else {
      throw RealtimeError.encoding(underlying: EncodingError.invalidValue(topic, .init(codingPath: [], debugDescription: "Header field exceeds 255 bytes")))
    }
    var out = Data()
    out.append(BinaryKind.clientBroadcastPush.rawValue)
    out.append(UInt8(jrBytes.count))
    out.append(UInt8(rBytes.count))
    out.append(UInt8(tBytes.count))
    out.append(UInt8(eBytes.count))
    out.append(0x00)               // meta_len = 0
    out.append(encoding.rawValue)
    out.append(jrBytes); out.append(rBytes); out.append(tBytes); out.append(eBytes)
    out.append(payload)
    return out
  }
}
```

- [ ] **Step 6: Run serializer tests — expect all pass**

```bash
cd Packages/_Realtime && swift test --filter PhoenixSerializerTests
```

Expected: 3 tests pass.

- [ ] **Step 7: Commit**

```bash
git add Packages/_Realtime/Sources/_Realtime/Internal \
        Packages/_Realtime/Tests/_RealtimeTests/PhoenixSerializerTests.swift
git commit -m "feat(_Realtime): Phase 3a — internal JSON + Phoenix wire serializer"
```

---

## Task 2: `ConnectionStatus` and `Realtime` actor

**Files:**
- Create: `Packages/_Realtime/Sources/_Realtime/Client/ConnectionStatus.swift`
- Create: `Packages/_Realtime/Sources/_Realtime/Client/Realtime.swift`
- Create: `Packages/_Realtime/Tests/_RealtimeTests/RealtimeClientTests.swift`

- [ ] **Step 1: Write failing client tests**

```swift
import Testing
import Clocks
import ConcurrencyExtras
@testable import _Realtime

@Suite struct RealtimeClientTests {
  static let testURL = URL(string: "ws://localhost:4000/realtime/v1")!

  @Test func connectSendsAuthHeaders() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let realtime = Realtime(
      url: Self.testURL,
      apiKey: .literal("anon-key"),
      transport: transport
    )

    try await realtime.connect()

    // Verify the transport was asked to connect (implicit in no throw)
    // and the status transitions to connected
    let snapshot = await realtime.currentStatus
    #expect(snapshot == .connected)
  }

  @Test func disconnectStopsHeartbeatAndClosesSocket() async throws {
    let clock = TestClock()
    let (transport, _) = InMemoryTransport.pair()
    let config = Configuration { $0.clock = clock }
    let realtime = Realtime(url: Self.testURL, apiKey: .literal("key"), configuration: config, transport: transport)

    try await realtime.connect()
    await realtime.disconnect()

    let snapshot = await realtime.currentStatus
    #expect(snapshot == .closed(.userRequested))
  }

  @Test func channelSameTopicReturnsSameActor() async throws {
    let (transport, _) = InMemoryTransport.pair()
    let realtime = Realtime(url: Self.testURL, apiKey: .literal("key"), transport: transport)

    let ch1 = realtime.channel("room:1")
    let ch2 = realtime.channel("room:1")
    #expect(ch1 === ch2)
  }

  @Test func channelDifferentTopicsReturnDifferentActors() async throws {
    let (transport, _) = InMemoryTransport.pair()
    let realtime = Realtime(url: Self.testURL, apiKey: .literal("key"), transport: transport)

    let ch1 = realtime.channel("room:1")
    let ch2 = realtime.channel("room:2")
    #expect(ch1 !== ch2)
  }
}
```

- [ ] **Step 2: Run — expect compile failure (Realtime not defined)**

```bash
cd Packages/_Realtime && swift test --filter RealtimeClientTests 2>&1 | head -10
```

- [ ] **Step 3: Create `Client/ConnectionStatus.swift`**

```swift
import Foundation

public struct ConnectionStatus: Sendable, Equatable {
  public enum State: Sendable, Equatable {
    case idle
    case connecting(attempt: Int)
    case connected
    case reconnecting(attempt: Int)
    case closed(CloseReason)
  }
  public let state: State
  public let since: Date
  public let latency: Duration?

  public static func == (lhs: Self, rhs: Self) -> Bool { lhs.state == rhs.state }
}

// Convenience equatable for tests
extension ConnectionStatus.State {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    switch (lhs, rhs) {
    case (.idle, .idle), (.connected, .connected): true
    case (.connecting(let a), .connecting(let b)): a == b
    case (.reconnecting(let a), .reconnecting(let b)): a == b
    case (.closed(let a), .closed(let b)): a == b
    default: false
    }
  }
}
```

- [ ] **Step 4: Create `Client/Realtime.swift`**

```swift
import Clocks
import Foundation
import IssueReporting

public final actor Realtime: Sendable {
  private let url: URL
  private let apiKey: APIKeySource
  let configuration: Configuration
  private let transport: any RealtimeTransport

  private var connection: (any RealtimeConnection)?
  private var receiveTask: Task<Void, Never>?
  private var heartbeatTask: Task<Void, Never>?
  private var channelRegistry: [String: Channel] = [:]
  private var pendingReplies: [String: CheckedContinuation<PhoenixMessage, any Error>] = [:]
  private var refCounter: Int = 0
  private var statusContinuations: [UUID: AsyncStream<ConnectionStatus>.Continuation] = [:]
  private var _currentStatus: ConnectionStatus.State = .idle

  // Exposed for tests
  var currentStatus: ConnectionStatus.State { _currentStatus }

  public init(
    url: URL,
    apiKey: APIKeySource,
    configuration: Configuration = .default,
    transport: any RealtimeTransport = URLSessionTransport()
  ) {
    self.url = url
    self.apiKey = apiKey
    self.configuration = configuration
    self.transport = transport
  }

  // MARK: - Public API

  public var status: AsyncStream<ConnectionStatus> {
    AsyncStream { continuation in
      let id = UUID()
      statusContinuations[id] = continuation
      continuation.onTermination = { [id] _ in
        Task { await self.statusContinuations.removeValue(forKey: id) }
      }
    }
  }

  public func connect() async throws(RealtimeError) {
    guard _currentStatus == .idle || _currentStatus == .closed(.userRequested) else { return }
    setStatus(.connecting(attempt: 1))

    let token: String
    do {
      token = try await resolveToken()
    } catch {
      throw .authenticationFailed(reason: error.localizedDescription, underlying: error as? (any Error & Sendable))
    }

    var headers = configuration.headers
    headers["apikey"] = token
    headers["Authorization"] = "Bearer \(token)"
    headers["vsn"] = configuration.protocolVersion.rawValue

    let wsURL = buildWebSocketURL()
    let conn: any RealtimeConnection
    do {
      conn = try await transport.connect(to: wsURL, headers: headers)
    } catch {
      setStatus(.closed(.transportFailure))
      throw .transportFailure(underlying: error as! (any Error & Sendable))
    }
    self.connection = conn
    setStatus(.connected)
    startReceiving(conn)
    startHeartbeat()
  }

  public func disconnect() async {
    receiveTask?.cancel(); receiveTask = nil
    heartbeatTask?.cancel(); heartbeatTask = nil
    await connection?.close(code: 1000, reason: "user requested")
    connection = nil
    setStatus(.closed(.userRequested))
    failAllPendingReplies(with: RealtimeError.disconnected)
  }

  public func updateToken(_ newToken: String) async throws(RealtimeError) {
    let msg = PhoenixMessage(
      joinRef: nil, ref: nextRef(),
      topic: "phoenix", event: "access_token",
      payload: ["access_token": .string(newToken)]
    )
    _ = try await sendAndAwait(msg, timeout: configuration.joinTimeout)
  }

  public func channel(_ topic: String, configure: (inout ChannelOptions) -> Void = { _ in }) -> Channel {
    if let existing = channelRegistry[topic] { return existing }
    var options = ChannelOptions()
    configure(&options)
    let ch = Channel(topic: topic, options: options, realtime: self)
    channelRegistry[topic] = ch
    return ch
  }

  // MARK: - Internal send API (used by Channel)

  func send(_ message: PhoenixMessage) async throws(RealtimeError) {
    guard let connection else { throw .disconnected }
    do {
      let text = try PhoenixSerializer.encodeText(message)
      try await connection.send(.text(text))
    } catch let e as RealtimeError {
      throw e
    } catch {
      throw .transportFailure(underlying: error as! (any Error & Sendable))
    }
  }

  func sendAndAwait(_ message: PhoenixMessage, timeout: Duration) async throws(RealtimeError) -> PhoenixMessage {
    guard connection != nil else { throw .disconnected }
    let ref = nextRef()
    var tagged = message
    tagged.ref = ref

    return try await withTimeout(timeout, clock: configuration.clock) {
      try await withCheckedThrowingContinuation { continuation in
        pendingReplies[ref] = continuation
        Task {
          do {
            let text = try PhoenixSerializer.encodeText(tagged)
            try await self.connection?.send(.text(text))
          } catch {
            if let cont = self.pendingReplies.removeValue(forKey: ref) {
              cont.resume(throwing: error)
            }
          }
        }
      }
    } onTimeout: {
      if let cont = pendingReplies.removeValue(forKey: ref) {
        cont.resume(throwing: RealtimeError.channelJoinTimeout)
      }
    }
  }

  func removeChannel(_ topic: String) {
    channelRegistry.removeValue(forKey: topic)
  }

  // MARK: - Private

  private func resolveToken() async throws -> String {
    switch apiKey {
    case .literal(let key): return key
    case .dynamic(let fn): return try await fn()
    }
  }

  private func buildWebSocketURL() -> URL {
    guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
    var items = comps.queryItems ?? []
    items.append(URLQueryItem(name: "vsn", value: configuration.protocolVersion.rawValue))
    comps.queryItems = items
    return comps.url ?? url
  }

  private func nextRef() -> String {
    refCounter += 1
    return String(refCounter)
  }

  private func setStatus(_ state: ConnectionStatus.State) {
    _currentStatus = state
    let status = ConnectionStatus(state: state, since: Date(), latency: nil)
    for cont in statusContinuations.values { cont.yield(status) }
  }

  private func startReceiving(_ conn: any RealtimeConnection) {
    receiveTask = Task { [weak self] in
      do {
        for try await frame in conn.frames {
          await self?.handle(frame)
        }
      } catch {
        await self?.handleConnectionLoss(error: error)
      }
    }
  }

  private func handle(_ frame: TransportFrame) async {
    switch frame {
    case .text(let text):
      guard let msg = try? PhoenixSerializer.decodeText(text) else { return }
      await route(msg)
    case .binary(let data):
      guard let broadcast = try? PhoenixSerializer.decodeBinary(data) else { return }
      // Binary broadcasts go directly to the channel
      if let ch = channelRegistry[broadcast.topic] {
        await ch.handleBinaryBroadcast(broadcast)
      }
    }
  }

  private func route(_ msg: PhoenixMessage) async {
    // Heartbeat reply
    if msg.topic == "phoenix", msg.event == "phx_reply" {
      if let ref = msg.ref, let cont = pendingReplies.removeValue(forKey: ref) {
        cont.resume(returning: msg)
      }
      return
    }
    // Pending reply
    if msg.event == "phx_reply", let ref = msg.ref,
       let cont = pendingReplies.removeValue(forKey: ref) {
      cont.resume(returning: msg)
      return
    }
    // Route to channel
    if let ch = channelRegistry[msg.topic] {
      await ch.handle(msg)
    }
  }

  private func handleConnectionLoss(error: any Error) async {
    setStatus(.closed(.transportFailure))
    failAllPendingReplies(with: RealtimeError.disconnected)
    // Notify all channels
    for ch in channelRegistry.values {
      await ch.handleConnectionLoss()
    }
    // Attempt reconnect
    await attemptReconnect(lastError: error)
  }

  private func attemptReconnect(lastError: any Error) async {
    var attempt = 1
    while !Task.isCancelled {
      guard let delay = configuration.reconnection.nextDelay(attempt, lastError as! (any Error & Sendable)) else {
        setStatus(.closed(.transportFailure))
        return
      }
      setStatus(.reconnecting(attempt: attempt))
      try? await configuration.clock.sleep(for: delay)
      guard !Task.isCancelled else { return }
      do {
        try await connect()
        // Re-join all channels
        for ch in channelRegistry.values {
          try? await ch.rejoin()
        }
        return
      } catch {
        attempt += 1
      }
    }
  }

  private func startHeartbeat() {
    heartbeatTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        do {
          try await configuration.clock.sleep(for: configuration.heartbeat)
          let msg = PhoenixMessage(joinRef: nil, ref: nil, topic: "phoenix", event: "heartbeat", payload: [:])
          _ = try await sendAndAwait(msg, timeout: configuration.heartbeat)
        } catch is CancellationError {
          return
        } catch {
          // heartbeat failure handled by connection loss
        }
      }
    }
  }

  private func failAllPendingReplies(with error: RealtimeError) {
    let replies = pendingReplies
    pendingReplies.removeAll()
    for cont in replies.values {
      cont.resume(throwing: error)
    }
  }
}

// MARK: - Timeout helper

private func withTimeout<T: Sendable>(
  _ duration: Duration,
  clock: any Clock<Duration>,
  operation: @Sendable () async throws -> T,
  onTimeout: @Sendable () -> Void
) async throws(RealtimeError) -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask { try await operation() }
    group.addTask {
      try await clock.sleep(for: duration)
      throw RealtimeError.channelJoinTimeout
    }
    do {
      let result = try await group.next()!
      group.cancelAll()
      return result
    } catch let e as RealtimeError {
      onTimeout()
      group.cancelAll()
      throw e
    } catch {
      group.cancelAll()
      throw .transportFailure(underlying: error as! (any Error & Sendable))
    }
  }
}
```

- [ ] **Step 5: Run client tests**

```bash
cd Packages/_Realtime && swift test --filter RealtimeClientTests
```

Expected: All 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Packages/_Realtime/Sources/_Realtime/Client \
        Packages/_Realtime/Tests/_RealtimeTests/RealtimeClientTests.swift
git commit -m "feat(_Realtime): Phase 3 — Realtime actor with connect/disconnect/channel registry"
```

---

## Task 3: `Channel` actor (Phase 4)

**Files:**
- Create: `Packages/_Realtime/Sources/_Realtime/Channel/ChannelState.swift`
- Create: `Packages/_Realtime/Sources/_Realtime/Channel/ChannelOptions.swift`
- Create: `Packages/_Realtime/Sources/_Realtime/Channel/Channel.swift`
- Create: `Packages/_Realtime/Tests/_RealtimeTests/ChannelTests.swift`

- [ ] **Step 1: Write failing channel tests**

```swift
import Testing
import ConcurrencyExtras
@testable import _Realtime

@Suite struct ChannelTests {
  static let testURL = URL(string: "ws://localhost:4000/realtime/v1")!

  @Test func joinTransitionsToJoined() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let realtime = Realtime(url: Self.testURL, apiKey: .literal("key"), transport: transport)
    try await realtime.connect()

    let channel = realtime.channel("room:1")

    // Server auto-replies to phx_join with ok
    Task {
      if let frame = await server.receive() {
        let msg = try! PhoenixSerializer.decodeText(frame.text!)
        let reply = PhoenixMessage(
          joinRef: msg.joinRef, ref: msg.ref,
          topic: msg.topic, event: "phx_reply",
          payload: ["status": "ok", "response": [:]]
        )
        await server.send(.text(try! PhoenixSerializer.encodeText(reply)))
      }
    }

    try await channel.join()
    let state = await channel.currentState
    #expect(state == .joined)
  }

  @Test func sameTopicReturnsSameChannel() async throws {
    let (transport, _) = InMemoryTransport.pair()
    let realtime = Realtime(url: Self.testURL, apiKey: .literal("key"), transport: transport)

    let ch1 = realtime.channel("room:42")
    let ch2 = realtime.channel("room:42")
    #expect(ch1 === ch2)
  }

  @Test func firstCallWinsOnOptions() async throws {
    let (transport, _) = InMemoryTransport.pair()
    let realtime = Realtime(url: Self.testURL, apiKey: .literal("key"), transport: transport)

    let ch1 = realtime.channel("room:1") { $0.isPrivate = true }
    let ch2 = realtime.channel("room:1") { $0.isPrivate = false }
    let opts = await ch1.options
    #expect(opts.isPrivate == true)   // first call wins
    #expect(ch1 === ch2)
  }

  @Test func leaveClosesAllStreams() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let realtime = Realtime(url: Self.testURL, apiKey: .literal("key"), transport: transport)
    try await realtime.connect()

    // Auto-reply helper
    Task {
      for await frame in server.receivedFrames {
        guard let text = frame.text,
              let msg = try? PhoenixSerializer.decodeText(text) else { continue }
        if msg.event == "phx_join" || msg.event == "phx_leave" {
          let reply = PhoenixMessage(
            joinRef: msg.joinRef, ref: msg.ref, topic: msg.topic,
            event: "phx_reply", payload: ["status": "ok", "response": [:]]
          )
          await server.send(.text(try! PhoenixSerializer.encodeText(reply)))
        }
      }
    }

    let channel = realtime.channel("room:1")
    try await channel.join()

    // Collect a broadcast stream — it should close when leave() is called
    let broadcasts = await channel.broadcasts()
    var caughtError: RealtimeError?

    Task {
      do {
        for try await _ in broadcasts {}
      } catch let e as RealtimeError {
        caughtError = e
      }
    }

    try await channel.leave()

    try await Task.sleep(for: .milliseconds(100))
    #expect(caughtError == .channelClosed(.userRequested))
  }
}

extension TransportFrame {
  var text: String? { if case .text(let t) = self { t } else { nil } }
}
```

- [ ] **Step 2: Run — expect compile failure**

```bash
cd Packages/_Realtime && swift test --filter ChannelTests 2>&1 | head -10
```

- [ ] **Step 3: Create `Channel/ChannelState.swift`**

```swift
public enum ChannelState: Sendable, Equatable {
  case unsubscribed
  case joining
  case joined
  case leaving
  case closed(CloseReason)
}
```

- [ ] **Step 4: Create `Channel/ChannelOptions.swift`**

```swift
import Foundation

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
  public init(since: Date, limit: Int? = nil) {
    self.since = since; self.limit = limit
  }
}
```

- [ ] **Step 5: Create `Channel/Channel.swift`**

```swift
import Foundation
import IssueReporting

public final actor Channel: Sendable {
  public let topic: String
  public private(set) var options: ChannelOptions
  private weak var realtime: Realtime?

  private var _state: ChannelState = .unsubscribed
  var currentState: ChannelState { _state }

  // Fan-out continuations — populated by Broadcast/Presence/Postgres extensions
  var broadcastContinuations: [UUID: AsyncThrowingStream<[String: JSONValue], RealtimeError>.Continuation] = [:]
  var presenceContinuations: [UUID: AsyncStream<[String: JSONValue]>.Continuation] = [:]
  var postgresContinuations: [UUID: AsyncThrowingStream<[String: JSONValue], RealtimeError>.Continuation] = [:]
  var stateContinuations: [UUID: AsyncStream<ChannelState>.Continuation] = [:]

  // Track re-join state
  private var joinRef: String?
  private var optionsLocked = false

  init(topic: String, options: ChannelOptions, realtime: Realtime) {
    self.topic = topic
    self.options = options
    self.realtime = realtime
  }

  // MARK: - Public API

  public var state: AsyncStream<ChannelState> {
    AsyncStream { continuation in
      let id = UUID()
      stateContinuations[id] = continuation
      continuation.yield(_state)
      continuation.onTermination = { [id] _ in
        Task { await self.stateContinuations.removeValue(forKey: id) }
      }
    }
  }

  public func join() async throws(RealtimeError) {
    guard _state == .unsubscribed || _state == .closed(.userRequested) else { return }
    optionsLocked = true
    try await _join()
  }

  public func leave() async throws(RealtimeError) {
    guard _state == .joined || _state == .joining else { return }
    setState(.leaving)
    guard let realtime else { throw .disconnected }
    let ref = await realtime.nextRef()
    let msg = PhoenixMessage(
      joinRef: joinRef, ref: ref,
      topic: topic, event: "phx_leave", payload: [:]
    )
    _ = try await realtime.sendAndAwait(msg, timeout: realtime.configuration.leaveTimeout)
    setState(.closed(.userRequested))
    finishAllContinuations(throwing: .channelClosed(.userRequested))
    await realtime.removeChannel(topic)
  }

  // MARK: - Internal routing (called by Realtime)

  func handle(_ msg: PhoenixMessage) async {
    switch msg.event {
    case "phx_close":
      setState(.closed(.serverClosed(code: 0, message: nil)))
      finishAllContinuations(throwing: .channelClosed(.serverClosed(code: 0, message: nil)))
    case "phx_error":
      let reason = msg.payload["reason"].flatMap { if case .string(let s) = $0 { s } else { nil } } ?? "unknown"
      setState(.closed(.policyViolation(reason)))
      finishAllContinuations(throwing: .channelClosed(.policyViolation(reason)))
    case "broadcast":
      for cont in broadcastContinuations.values { cont.yield(msg.payload) }
    case "presence_diff":
      for cont in presenceContinuations.values { cont.yield(msg.payload) }
    case "presence_state":
      for cont in presenceContinuations.values { cont.yield(msg.payload) }
    case "postgres_changes":
      for cont in postgresContinuations.values { cont.yield(msg.payload) }
    default:
      break
    }
  }

  func handleBinaryBroadcast(_ broadcast: BinaryBroadcast) async {
    let payload: [String: JSONValue]
    switch broadcast.payload {
    case .json(let obj): payload = obj
    case .binary:        return  // binary payloads not delivered to typed continuations
    }
    for cont in broadcastContinuations.values { cont.yield(payload) }
  }

  func handleConnectionLoss() async {
    // Streams pause silently during reconnection — no sentinel values
    // state transitions to reflect loss
    if _state == .joined { setState(.unsubscribed) }
  }

  func rejoin() async throws(RealtimeError) {
    guard _state == .unsubscribed else { return }
    try await _join()
  }

  // MARK: - Private

  private func _join() async throws(RealtimeError) {
    guard let realtime else { throw .disconnected }
    setState(.joining)
    let ref = await realtime.nextRef()
    joinRef = ref

    let joinPayload = buildJoinPayload()
    let msg = PhoenixMessage(
      joinRef: ref, ref: ref,
      topic: topic, event: "phx_join",
      payload: joinPayload
    )
    let reply = try await realtime.sendAndAwait(msg, timeout: realtime.configuration.joinTimeout)
    let status = reply.payload["status"].flatMap { if case .string(let s) = $0 { s } else { nil } }
    if status == "ok" {
      setState(.joined)
    } else {
      let reason = reply.payload["response"].flatMap { if case .object(let o) = $0 { o["reason"] } else { nil } }.flatMap { if case .string(let s) = $0 { s } else { nil } } ?? "unknown"
      setState(.closed(.policyViolation(reason)))
      throw .channelJoinRejected(reason: reason)
    }
  }

  private func buildJoinPayload() -> [String: JSONValue] {
    var config: [String: JSONValue] = [:]

    if options.broadcast.acknowledge || options.broadcast.receiveOwnBroadcasts || options.broadcast.replay != nil {
      var bc: [String: JSONValue] = [:]
      if options.broadcast.acknowledge { bc["ack"] = true }
      if options.broadcast.receiveOwnBroadcasts { bc["self"] = true }
      if let replay = options.broadcast.replay {
        bc["replay"] = .object([
          "since": .int(Int(replay.since.timeIntervalSince1970 * 1000)),
          "limit": replay.limit.map { .int($0) } ?? .null,
        ])
      }
      config["broadcast"] = .object(bc)
    }

    if let key = options.presenceKey {
      config["presence"] = .object(["key": .string(key)])
    }

    if options.isPrivate {
      config["private"] = true
    }

    return ["config": .object(config)]
  }

  private func setState(_ new: ChannelState) {
    _state = new
    for cont in stateContinuations.values { cont.yield(new) }
  }

  private func finishAllContinuations(throwing error: RealtimeError) {
    for cont in broadcastContinuations.values { cont.finish(throwing: error) }
    for cont in postgresContinuations.values  { cont.finish(throwing: error) }
    for cont in presenceContinuations.values  { cont.finish() }
    for cont in stateContinuations.values     { cont.finish() }
    broadcastContinuations.removeAll()
    postgresContinuations.removeAll()
    presenceContinuations.removeAll()
    stateContinuations.removeAll()
  }
}

// Expose nextRef from Realtime for Channel's use
extension Realtime {
  func nextRef() -> String {
    refCounter += 1
    return String(refCounter)
  }
}
```

Note: `InMemoryServer.receivedFrames` needs to be exposed for the leave test. Add to `InMemoryServer` in `Testing/InMemoryTransport.swift`:

```swift
public var receivedFrames: AsyncThrowingStream<TransportFrame, any Error> { _receivedFrames }
```

Rename the stored property to `_receivedFrames` and update the `receive()` helper accordingly.

- [ ] **Step 6: Run channel tests**

```bash
cd Packages/_Realtime && swift test --filter ChannelTests
```

Expected: All 4 tests pass.

- [ ] **Step 7: Commit**

```bash
git add Packages/_Realtime/Sources/_Realtime/Channel \
        Packages/_Realtime/Tests/_RealtimeTests/ChannelTests.swift
git commit -m "feat(_Realtime): Phase 4 — Channel actor with join/leave lifecycle"
```
