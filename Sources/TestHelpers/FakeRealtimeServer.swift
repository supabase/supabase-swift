//
//  FakeRealtimeServer.swift
//  TestHelpers
//
//  Created by Guilherme Souza on 06/10/26.
//

import ConcurrencyExtras
package import Foundation
package import HTTPTypes
package import Helpers
package import Realtime

/// A `WebSocketTransport` whose connections go to a ``FakeRealtimeServer`` instead of the network.
package struct StubWebSocketTransport: WebSocketTransport {
  package let server: FakeRealtimeServer

  package init(server: FakeRealtimeServer) {
    self.server = server
  }

  package func connect(to url: URL, headerFields: HTTPFields) async throws
    -> any WebSocketConnection
  {
    try server.accept(url: url, headerFields: headerFields)
  }
}

/// An in-memory Realtime server that speaks the Phoenix v2 wire format.
///
/// It records every frame the client sends, answers joins, heartbeats, leaves and presence
/// pushes the way the real server does, and lets a test push any server message, deliver raw
/// frames, close the socket with any code, or refuse the next upgrade. Replies are delivered
/// synchronously unless ``joinReplyDelay`` is set, in which case they wait on the injected
/// clock.
package final class FakeRealtimeServer: Sendable {
  /// How the server answers a `phx_join`.
  package enum JoinReply: Sendable {
    /// `status: "ok"`, echoing each postgres binding with an integer `id`.
    case ok
    /// `status: "error"` with `response.reason`.
    case error(reason: String)
    /// No reply, as when the server is overloaded or the frame was lost.
    case silent
  }

  private struct State {
    var joinReply: JoinReply = .ok
    var joinReplyDelay: Duration = .zero
    var repliesToHeartbeats = true
    var acknowledgesBroadcasts = false
    var dropsClientFrames = false
    var failsNextSend = false
    var pendingUpgradeRefusal: Int?
    var connectCount = 0
    var upgradeURL: URL?
    var upgradeHeaders: HTTPFields = [:]
    var current: StubWebSocketConnection?
    var sentFrames: [WebSocketFrame] = []
    var sentMessages: [RealtimeMessageV2] = []
    var joinRefs: [String: String] = [:]
    var clientCloseCode: WebSocketCloseCode?
    var clientCloseReason: String?
    var nextBindingID = 1
  }

  private let state = LockIsolated(State())
  private let clock: any Clock<Duration>
  private let serializer = RealtimeSerializer()

  package init(clock: any Clock<Duration> = ContinuousClock()) {
    self.clock = clock
  }

  /// A transport that connects to this server.
  package var transport: StubWebSocketTransport { StubWebSocketTransport(server: self) }

  // MARK: Configuration

  package var joinReply: JoinReply {
    get { state.value.joinReply }
    set { state.withValue { $0.joinReply = newValue } }
  }

  /// How long a join reply waits on the clock. The real server delays error replies by 5 s.
  package var joinReplyDelay: Duration {
    get { state.value.joinReplyDelay }
    set { state.withValue { $0.joinReplyDelay = newValue } }
  }

  package var repliesToHeartbeats: Bool {
    get { state.value.repliesToHeartbeats }
    set { state.withValue { $0.repliesToHeartbeats = newValue } }
  }

  /// Whether a `broadcast` push gets an `ok` reply, as the real server does with `ack: true`.
  package var acknowledgesBroadcasts: Bool {
    get { state.value.acknowledgesBroadcasts }
    set { state.withValue { $0.acknowledgesBroadcasts = newValue } }
  }

  /// When `true`, client frames are recorded but never answered.
  package var dropsClientFrames: Bool {
    get { state.value.dropsClientFrames }
    set { state.withValue { $0.dropsClientFrames = newValue } }
  }

  /// The client's next `send` throws, as a dead socket would.
  package var failsNextSend: Bool {
    get { state.value.failsNextSend }
    set { state.withValue { $0.failsNextSend = newValue } }
  }

  func takeSendFailure() -> Bool {
    state.withValue { state in
      defer { state.failsNextSend = false }
      return state.failsNextSend
    }
  }

  /// Makes the next `connect` throw `RealtimeError.upgradeFailed(status:)`.
  package func refuseNextUpgrade(status: Int) {
    state.withValue { $0.pendingUpgradeRefusal = status }
  }

  // MARK: Observation

  package var connectCount: Int { state.value.connectCount }
  /// The URL of the last upgrade request.
  package var upgradeURL: URL? { state.value.upgradeURL }
  /// The header fields of the last upgrade request.
  package var upgradeHeaders: HTTPFields { state.value.upgradeHeaders }
  package var isConnected: Bool { state.value.current != nil }
  /// Every frame the client sent over any connection, in send order.
  package var sentFrames: [WebSocketFrame] { state.value.sentFrames }
  /// The text frames and kind-3 binary pushes the client sent, decoded, in send order.
  package var sentMessages: [RealtimeMessageV2] { state.value.sentMessages }
  package var clientCloseCode: WebSocketCloseCode? { state.value.clientCloseCode }
  package var clientCloseReason: String? { state.value.clientCloseReason }

  // MARK: Server → client

  package func push(_ message: RealtimeMessageV2) {
    // A message this fake built from JSON values always encodes.
    guard let text = try? serializer.encodeText(message) else { return }
    deliver(.text(text))
  }

  /// A channel push with the topic's current `join_ref`, as the channel process sends.
  package func pushChannel(topic: String, event: String, payload: JSONObject) {
    let joinRef = state.value.joinRefs[topic]
    push(
      RealtimeMessageV2(joinRef: joinRef, ref: nil, topic: topic, event: event, payload: payload))
  }

  /// A fastlane push with no `join_ref`, as broadcasts, presence diffs and changes arrive.
  package func pushFastlane(topic: String, event: String, payload: JSONObject) {
    push(RealtimeMessageV2(joinRef: nil, ref: nil, topic: topic, event: event, payload: payload))
  }

  package func pushSystem(
    topic: String, status: String, message: String, extension: String = "system"
  ) {
    pushChannel(
      topic: topic, event: "system",
      payload: [
        "extension": .string(`extension`), "status": .string(status),
        "message": .string(message), "channel": .string(Self.subtopic(topic)),
      ])
  }

  package func pushPresenceState(topic: String, state: JSONObject) {
    pushChannel(topic: topic, event: "presence_state", payload: state)
  }

  package func pushPresenceDiff(topic: String, joins: JSONObject, leaves: JSONObject) {
    pushFastlane(
      topic: topic, event: "presence_diff",
      payload: ["joins": .object(joins), "leaves": .object(leaves)])
  }

  package func pushPostgresChanges(topic: String, ids: [Int], data: JSONObject) {
    pushFastlane(
      topic: topic, event: "postgres_changes",
      payload: ["ids": .array(ids.map { .integer($0) }), "data": .object(data)])
  }

  /// A kind-4 binary broadcast with a JSON payload, as database-originated broadcasts arrive.
  package func pushBroadcast(
    topic: String, event: String, payload: JSONObject, meta: JSONObject? = nil
  ) {
    guard let payloadData = try? JSONEncoder().encode(payload) else { return }
    deliver(
      .binary(
        Self.encodeUserBroadcast(
          topic: topic, event: event, meta: meta, encoding: 1, payload: payloadData)))
  }

  /// A kind-4 binary broadcast with a raw payload.
  package func pushBroadcast(topic: String, event: String, data: Data, meta: JSONObject? = nil) {
    deliver(
      .binary(
        Self.encodeUserBroadcast(topic: topic, event: event, meta: meta, encoding: 0, payload: data)
      ))
  }

  /// `phx_error`: the channel process crashed.
  package func errorChannel(topic: String) {
    pushChannel(topic: topic, event: "phx_error", payload: [:])
  }

  /// `phx_close`: the channel stopped.
  package func closeChannel(topic: String) {
    pushChannel(topic: topic, event: "phx_close", payload: [:])
    state.withValue { $0.joinRefs[topic] = nil }
  }

  /// Delivers a raw frame, malformed or not, to the current connection.
  package func deliver(_ frame: WebSocketFrame) {
    state.value.current?.deliver(frame)
  }

  /// Closes the current connection from the server side.
  package func closeConnection(code: WebSocketCloseCode?, reason: String?) {
    let connection = state.withValue { state -> StubWebSocketConnection? in
      defer { state.current = nil }
      return state.current
    }
    connection?.finish(code: code, reason: reason)
  }

  // MARK: Client → server

  func accept(url: URL, headerFields: HTTPFields) throws -> StubWebSocketConnection {
    let connection = StubWebSocketConnection(server: self)
    try state.withValue { state in
      state.upgradeURL = url
      state.upgradeHeaders = headerFields
      if let status = state.pendingUpgradeRefusal {
        state.pendingUpgradeRefusal = nil
        throw RealtimeError.upgradeFailed(status: status)
      }
      state.connectCount += 1
      state.current = connection
    }
    return connection
  }

  func receive(_ frame: WebSocketFrame, from connection: StubWebSocketConnection) {
    let message = decode(frame)
    let (dropped, delay) = state.withValue { state -> (Bool, Duration) in
      state.sentFrames.append(frame)
      if let message { state.sentMessages.append(message) }
      return (state.dropsClientFrames, state.joinReplyDelay)
    }
    guard !dropped, let message else { return }

    switch message.event {
    case "phx_join":
      state.withValue { $0.joinRefs[message.topic] = message.ref }
      let reply = joinReplyMessage(for: message)
      guard let reply else { return }
      if delay > .zero {
        Task {
          try await clock.sleep(for: delay)
          push(reply)
        }
      } else {
        push(reply)
      }
    case "heartbeat" where state.value.repliesToHeartbeats:
      push(okReply(to: message))
    case "phx_leave":
      push(okReply(to: message))
      closeChannel(topic: message.topic)
    case "presence":
      push(okReply(to: message))
    case "broadcast" where state.value.acknowledgesBroadcasts:
      push(okReply(to: message))
    default:
      break
    }
  }

  func clientClosed(code: WebSocketCloseCode?, reason: String?) {
    state.withValue {
      $0.clientCloseCode = code
      $0.clientCloseReason = reason
      $0.current = nil
    }
  }

  // MARK: Wire format

  private func decode(_ frame: WebSocketFrame) -> RealtimeMessageV2? {
    switch frame {
    case .text(let text): return try? serializer.decodeText(text)
    case .binary(let data): return Self.decodeUserBroadcastPush(data)
    }
  }

  private func okReply(to message: RealtimeMessageV2) -> RealtimeMessageV2 {
    RealtimeMessageV2(
      joinRef: message.joinRef, ref: message.ref, topic: message.topic, event: "phx_reply",
      payload: ["status": "ok", "response": [:]])
  }

  private func joinReplyMessage(for join: RealtimeMessageV2) -> RealtimeMessageV2? {
    switch state.value.joinReply {
    case .silent:
      return nil
    case .error(let reason):
      return RealtimeMessageV2(
        joinRef: join.ref, ref: join.ref, topic: join.topic, event: "phx_reply",
        payload: ["status": "error", "response": ["reason": .string(reason)]])
    case .ok:
      let bindings =
        join.payload["config"]?.objectValue?["postgres_changes"]?.arrayValue?
        .compactMap(\.objectValue) ?? []
      let echoed = state.withValue { state in
        bindings.map { binding -> JSONValue in
          defer { state.nextBindingID += 1 }
          return .object(binding.merging(["id": .integer(state.nextBindingID)]) { $1 })
        }
      }
      return RealtimeMessageV2(
        joinRef: join.ref, ref: join.ref, topic: join.topic, event: "phx_reply",
        payload: ["status": "ok", "response": ["postgres_changes": .array(echoed)]])
    }
  }

  private static func subtopic(_ topic: String) -> String {
    topic.hasPrefix("realtime:") ? String(topic.dropFirst("realtime:".count)) : topic
  }

  /// Kind 4: `[4][topic_len][event_len][meta_len][enc][topic][event][meta][payload]`.
  private static func encodeUserBroadcast(
    topic: String, event: String, meta: JSONObject?, encoding: UInt8, payload: Data
  ) -> Data {
    let metaBytes = meta.flatMap { try? JSONEncoder().encode($0) } ?? Data()
    var data = Data([
      4, UInt8(topic.utf8.count), UInt8(event.utf8.count), UInt8(metaBytes.count), encoding,
    ])
    data.append(Data(topic.utf8))
    data.append(Data(event.utf8))
    data.append(metaBytes)
    data.append(payload)
    return data
  }

  /// Kind 3: `[3][join_ref_len][ref_len][topic_len][event_len][meta_len][enc]` then the fields.
  private static func decodeUserBroadcastPush(_ data: Data) -> RealtimeMessageV2? {
    guard data.count >= 7, data[data.startIndex] == 3 else { return nil }
    let lengths = (1...5).map { Int(data[data.startIndex + $0]) }
    let encoding = data[data.startIndex + 6]
    var offset = data.startIndex + 7
    guard data.count >= offset + lengths.reduce(0, +) else { return nil }
    func field(_ length: Int) -> Data {
      defer { offset += length }
      return data[offset..<(offset + length)]
    }
    let joinRef = String(decoding: field(lengths[0]), as: UTF8.self)
    let ref = String(decoding: field(lengths[1]), as: UTF8.self)
    let topic = String(decoding: field(lengths[2]), as: UTF8.self)
    let event = String(decoding: field(lengths[3]), as: UTF8.self)
    _ = field(lengths[4])
    let payloadData = data[offset...]
    var payload: JSONObject = ["type": "broadcast", "event": .string(event)]
    if encoding == 1, let json = try? JSONDecoder().decode(JSONObject.self, from: payloadData) {
      payload["payload"] = .object(json)
    }
    return RealtimeMessageV2(
      joinRef: joinRef.isEmpty ? nil : joinRef, ref: ref.isEmpty ? nil : ref, topic: topic,
      event: "broadcast", payload: payload)
  }
}

/// The client end of a ``FakeRealtimeServer`` connection.
final class StubWebSocketConnection: WebSocketConnection {
  let events: AsyncStream<WebSocketEvent>
  private let continuation: AsyncStream<WebSocketEvent>.Continuation
  private let server: FakeRealtimeServer
  private let isClosed = LockIsolated(false)

  init(server: FakeRealtimeServer) {
    self.server = server
    (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
  }

  func send(_ frame: WebSocketFrame) async throws {
    guard !isClosed.value else {
      throw RealtimeError(kind: .notConnected, message: "WebSocket is closed.")
    }
    if server.takeSendFailure() {
      throw RealtimeError(kind: .transport, message: "simulated send failure")
    }
    server.receive(frame, from: self)
  }

  func close(code: WebSocketCloseCode, reason: String?) async {
    guard !isClosed.value else { return }
    server.clientClosed(code: code, reason: reason)
    finish(code: code, reason: reason)
  }

  func deliver(_ frame: WebSocketFrame) {
    guard !isClosed.value else { return }
    continuation.yield(.frame(frame))
  }

  func finish(code: WebSocketCloseCode?, reason: String?) {
    let wasClosed = isClosed.withValue { closed in
      defer { closed = true }
      return closed
    }
    guard !wasClosed else { return }
    continuation.yield(.closed(code: code, reason: reason))
    continuation.finish()
  }
}
