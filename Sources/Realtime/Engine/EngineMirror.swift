//
//  EngineMirror.swift
//  Realtime
//
//  Created by Guilherme Souza on 08/10/26.
//

import ConcurrencyExtras
import Foundation

/// Lock-protected state the engine writes and public handles read synchronously.
///
/// Never yield or call out while holding the lock: copy what is needed out first.
package final class EngineMirror: Sendable {
  private struct State {
    var connection: RealtimeConnectionStatus = .disconnected(nil)
    var channels: [String: RealtimeChannelStatus] = [:]
    var postgresChangeIDs: [String: [Int]] = [:]
    var heartbeats: [UUID: AsyncStream<HeartbeatEvent>.Continuation] = [:]
    var inbound: [String: [UUID: AsyncStream<ChannelInbound>.Continuation]] = [:]
  }

  private let state = LockIsolated(State())

  package init() {}

  package var connection: RealtimeConnectionStatus { state.connection }

  /// `.unsubscribed` for a topic the engine does not know.
  package func channel(_ topic: String) -> RealtimeChannelStatus {
    state.channels[topic] ?? .unsubscribed
  }

  package func postgresChangeIDs(_ topic: String) -> [Int] {
    state.postgresChangeIDs[topic] ?? []
  }

  func setConnection(_ status: RealtimeConnectionStatus) {
    state.withValue { $0.connection = status }
  }

  func setChannel(_ topic: String, _ status: RealtimeChannelStatus) {
    state.withValue { $0.channels[topic] = status }
  }

  func setPostgresChangeIDs(_ topic: String, _ ids: [Int]) {
    state.withValue { $0.postgresChangeIDs[topic] = ids }
  }

  func removeChannel(_ topic: String) {
    state.withValue {
      $0.channels[topic] = nil
      $0.postgresChangeIDs[topic] = nil
    }
  }

  func heartbeats() -> AsyncStream<HeartbeatEvent> {
    let (stream, continuation) = AsyncStream<HeartbeatEvent>.makeStream(
      bufferingPolicy: .unbounded)
    let id = UUID()
    continuation.onTermination = { [weak self] _ in
      self?.state.withValue { $0.heartbeats[id] = nil }
    }
    state.withValue { $0.heartbeats[id] = continuation }
    return stream
  }

  func yieldHeartbeat(_ event: HeartbeatEvent) {
    for continuation in state.heartbeats.values { continuation.yield(event) }
  }

  /// Every message on the topic, unbounded. Registers before it returns; ending the iteration
  /// removes the listener.
  package func inbound(_ topic: String) -> AsyncStream<ChannelInbound> {
    let (stream, continuation) = AsyncStream<ChannelInbound>.makeStream(
      bufferingPolicy: .unbounded)
    let id = UUID()
    continuation.onTermination = { [weak self] _ in
      self?.removeInbound(id, from: topic)
    }
    state.withValue { $0.inbound[topic, default: [:]][id] = continuation }
    return stream
  }

  package func listenerCount(_ topic: String) -> Int {
    state.inbound[topic]?.count ?? 0
  }

  package func yield(_ value: ChannelInbound, to topic: String) {
    let continuations = state.inbound[topic] ?? [:]
    for continuation in continuations.values { continuation.yield(value) }
  }

  package func finishInbound(_ topic: String) {
    let continuations = state.withValue { $0.inbound.removeValue(forKey: topic) } ?? [:]
    for continuation in continuations.values { continuation.finish() }
  }

  private func removeInbound(_ id: UUID, from topic: String) {
    state.withValue { state in
      state.inbound[topic]?[id] = nil
      if state.inbound[topic]?.isEmpty == true { state.inbound[topic] = nil }
    }
  }
}
