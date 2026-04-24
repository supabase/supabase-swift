//
//  Channel.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/25.
//

import Foundation

public final actor Channel: Sendable {
  public let topic: String
  public private(set) var options: ChannelOptions
  private weak var realtime: Realtime?

  private var _state: ChannelState = .unsubscribed
  var currentState: ChannelState { _state }

  // Fan-out continuation dictionaries — populated by Phase 5/6/7 extensions
  var broadcastContinuations: [UUID: AsyncThrowingStream<[String: JSONValue], any Error>.Continuation] = [:]
  var presenceContinuations: [UUID: AsyncStream<[String: JSONValue]>.Continuation] = [:]
  var postgresContinuations: [UUID: AsyncThrowingStream<[String: JSONValue], any Error>.Continuation] = [:]
  var stateContinuations: [UUID: AsyncStream<ChannelState>.Continuation] = [:]

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
        Task { await self.removeStateContinuation(id: id) }
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
    let config = realtime.configuration
    let msg = PhoenixMessage(
      joinRef: joinRef, ref: nil,
      topic: topic, event: "phx_leave", payload: [:]
    )
    _ = try await realtime.sendAndAwait(msg, timeout: config.leaveTimeout)
    setState(.closed(.userRequested))
    finishAllContinuations(throwing: .channelClosed(.userRequested))
    await realtime.removeChannel(topic)
  }

  // MARK: - Minimal stub for Phase 5 to compile tests
  // Full implementation in Channel+Broadcast.swift (Phase 5)
  func broadcasts() -> AsyncThrowingStream<[String: JSONValue], any Error> {
    AsyncThrowingStream { continuation in
      let id = UUID()
      broadcastContinuations[id] = continuation
      continuation.onTermination = { [id] _ in
        Task { await self.removeBroadcastContinuation(id: id) }
      }
    }
  }

  // MARK: - Internal routing (called by Realtime actor)

  func handle(_ msg: PhoenixMessage) async {
    switch msg.event {
    case "phx_close":
      let reason = CloseReason.serverClosed(code: 0, message: nil)
      setState(.closed(reason))
      finishAllContinuations(throwing: .channelClosed(reason))
    case "phx_error":
      let reasonStr = msg.payload["reason"].flatMap {
        if case .string(let s) = $0 { return s } else { return nil }
      } ?? "unknown"
      let reason = CloseReason.policyViolation(reasonStr)
      setState(.closed(reason))
      finishAllContinuations(throwing: .channelClosed(reason))
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
    guard case .json(let obj) = broadcast.payload else { return }
    for cont in broadcastContinuations.values { cont.yield(obj) }
  }

  func handleConnectionLoss() async {
    if _state == .joined || _state == .joining {
      setState(.unsubscribed)
    }
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
      joinRef: ref, ref: nil,
      topic: topic, event: "phx_join",
      payload: joinPayload
    )
    let config = realtime.configuration
    let reply = try await realtime.sendAndAwait(msg, timeout: config.joinTimeout)
    let status = reply.payload["status"].flatMap {
      if case .string(let s) = $0 { return s } else { return nil }
    }
    if status == "ok" {
      setState(.joined)
    } else {
      let responseObj = reply.payload["response"].flatMap {
        if case .object(let o) = $0 { return o } else { return nil }
      }
      let reason = responseObj?["reason"].flatMap {
        if case .string(let s) = $0 { return s } else { return nil }
      } ?? "rejected"
      setState(.closed(.policyViolation(reason)))
      throw .channelJoinRejected(reason: reason)
    }
  }

  private func buildJoinPayload() -> [String: JSONValue] {
    var config: [String: JSONValue] = [:]

    var bc: [String: JSONValue] = [:]
    if options.broadcast.acknowledge { bc["ack"] = true }
    if options.broadcast.receiveOwnBroadcasts { bc["self"] = true }
    if let replay = options.broadcast.replay {
      bc["replay"] = .object([
        "since": .int(Int(replay.since.timeIntervalSince1970 * 1000)),
        "limit": replay.limit.map { .int($0) } ?? .null,
      ])
    }
    if !bc.isEmpty { config["broadcast"] = .object(bc) }

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

  func finishAllContinuations(throwing error: RealtimeError) {
    let err: any Error = error
    for cont in broadcastContinuations.values { cont.finish(throwing: err) }
    for cont in postgresContinuations.values  { cont.finish(throwing: err) }
    for cont in presenceContinuations.values  { cont.finish() }
    for cont in stateContinuations.values     { cont.finish() }
    broadcastContinuations.removeAll()
    postgresContinuations.removeAll()
    presenceContinuations.removeAll()
    stateContinuations.removeAll()
  }

  // MARK: - Continuation cleanup helpers (called from onTermination Tasks)

  private func removeStateContinuation(id: UUID) {
    stateContinuations.removeValue(forKey: id)
  }

  private func removeBroadcastContinuation(id: UUID) {
    broadcastContinuations.removeValue(forKey: id)
  }

  func removePresenceContinuation(id: UUID) {
    presenceContinuations.removeValue(forKey: id)
  }

  func removePostgresContinuation(id: UUID) {
    postgresContinuations.removeValue(forKey: id)
  }
}
