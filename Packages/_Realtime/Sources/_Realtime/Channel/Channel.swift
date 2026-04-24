//
//  Channel.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/25.
//

import Foundation

struct PostgresSubscription: Sendable {
  let id: UUID
  let schema: String
  let table: String
  let filter: String?
}

public final actor Channel: Sendable {
  public let topic: String
  public private(set) var options: ChannelOptions
  weak var realtime: Realtime?

  private var _state: ChannelState = .unsubscribed
  var currentState: ChannelState { _state }

  // Fan-out continuation dictionaries — populated by Phase 5/6/7 extensions
  var broadcastContinuations:
    [UUID: AsyncThrowingStream<BroadcastMessage, any Error>.Continuation] = [:]
  var stateContinuations: [UUID: AsyncStream<ChannelState>.Continuation] = [:]

  // Presence handler registrations
  var presenceSnapshotHandlers: [UUID: @Sendable ([String: JSONValue]) -> Void] = [:]
  var presenceDiffHandlers: [UUID: @Sendable ([String: JSONValue]) -> Void] = [:]
  var presenceFinishHandlers: [UUID: @Sendable () -> Void] = [:]
  // Track registry: presenceTrackId → state, for auto re-track on rejoin
  var trackedStates: [UUID: [String: JSONValue]] = [:]

  // Postgres Changes handler registrations
  var postgresHandlers: [UUID: @Sendable ([String: JSONValue]) -> Void] = [:]
  var postgresFinishHandlers: [UUID: @Sendable () -> Void] = [:]
  var _postgresSubscriptions: [UUID: PostgresSubscription] = [:]

  var joinRef: String?

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
    switch _state {
    case .unsubscribed, .closed:
      break  // allowed to join
    default:
      return  // already joining, joined, or leaving
    }
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
    trackedStates.removeAll()
    _postgresSubscriptions.removeAll()
    finishAllContinuations(throwing: .channelClosed(.userRequested))
    await realtime.removeChannel(topic)
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
      }
      let reason = CloseReason.serverClosed(code: 0, message: reasonStr)
      setState(.closed(reason))
      finishAllContinuations(throwing: .channelClosed(reason))
    case "broadcast":
      await deliverBroadcast(from: msg.payload)
    case "presence_state":
      for handler in presenceSnapshotHandlers.values { handler(msg.payload) }
    case "presence_diff":
      for handler in presenceDiffHandlers.values { handler(msg.payload) }
    case "postgres_changes":
      for handler in postgresHandlers.values { handler(msg.payload) }
    default:
      break
    }
  }

  func handleBinaryBroadcast(_ broadcast: BinaryBroadcast) async {
    guard case .json(let obj) = broadcast.payload else { return }
    await deliverBroadcast(event: broadcast.event, payload: .object(obj))
  }

  /// Converts a raw Phoenix broadcast payload dict to `BroadcastMessage` and fans out to subscribers.
  func deliverBroadcast(from payload: [String: JSONValue]) async {
    guard let eventValue = payload["event"],
      case .string(let event) = eventValue
    else { return }
    let innerPayload: JSONValue = payload["payload"] ?? .object([:])
    await deliverBroadcast(event: event, payload: innerPayload)
  }

  private func deliverBroadcast(event: String, payload: JSONValue) async {
    let msg = BroadcastMessage(event: event, payload: payload)
    for cont in broadcastContinuations.values { cont.yield(msg) }
  }

  func handleConnectionLoss() async {
    if _state == .joined || _state == .joining {
      setState(.unsubscribed)
    }
  }

  func rejoin() async throws(RealtimeError) {
    guard _state == .unsubscribed else { return }
    try await _join()
    // Re-track all live presence handles after rejoining
    guard let realtime else { return }
    for (_, state) in trackedStates {
      let msg = PhoenixMessage(
        joinRef: joinRef, ref: nil,
        topic: topic, event: "presence",
        payload: ["event": "track", "payload": .object(state)]
      )
      try? await realtime.sendAndAwait(msg, timeout: realtime.configuration.joinTimeout)
    }
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
      let reason =
        responseObj?["reason"].flatMap {
          if case .string(let s) = $0 { return s } else { return nil }
        } ?? "rejected"
      setState(.closed(.policyViolation(reason)))
      trackedStates.removeAll()
      _postgresSubscriptions.removeAll()
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

    // Add postgres_changes subscriptions
    let changes: [JSONValue] = _postgresSubscriptions.values.map { sub in
      var entry: [String: JSONValue] = [
        "event": "*",
        "schema": .string(sub.schema),
        "table": .string(sub.table),
      ]
      if let f = sub.filter { entry["filter"] = .string(f) }
      return .object(entry)
    }
    if !changes.isEmpty { config["postgres_changes"] = .array(changes) }

    return ["config": .object(config)]
  }

  private func setState(_ new: ChannelState) {
    _state = new
    for cont in stateContinuations.values { cont.yield(new) }
  }

  func finishAllContinuations(throwing error: RealtimeError) {
    let err: any Error = error
    for cont in broadcastContinuations.values { cont.finish(throwing: err) }
    for cont in stateContinuations.values { cont.finish() }
    broadcastContinuations.removeAll()
    stateContinuations.removeAll()
    for finish in presenceFinishHandlers.values { finish() }
    presenceSnapshotHandlers.removeAll()
    presenceDiffHandlers.removeAll()
    presenceFinishHandlers.removeAll()
    for finish in postgresFinishHandlers.values { finish() }
    postgresHandlers.removeAll()
    postgresFinishHandlers.removeAll()
    // Note: trackedStates is intentionally NOT cleared here — transient errors
    // (phx_close / phx_error) should preserve tracked states so rejoin() can re-track them.
    // trackedStates is cleared only on permanent closes: leave() and _join() rejection.
  }

  // MARK: - Continuation cleanup helpers (called from onTermination Tasks)

  func joinIfNeeded() async throws(RealtimeError) {
    switch _state {
    case .unsubscribed, .closed:
      try await _join()
    default:
      break
    }
  }

  func registerBroadcastContinuation(
    id: UUID,
    continuation: AsyncThrowingStream<BroadcastMessage, any Error>.Continuation
  ) {
    broadcastContinuations[id] = continuation
  }

  private func removeStateContinuation(id: UUID) {
    stateContinuations.removeValue(forKey: id)
  }

  func removeBroadcastContinuation(id: UUID) {
    broadcastContinuations.removeValue(forKey: id)
  }
}
