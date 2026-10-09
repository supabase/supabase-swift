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
}
