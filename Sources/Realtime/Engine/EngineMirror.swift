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
    var channelStatuses: [String: [UUID: AsyncStream<RealtimeChannelStatus>.Continuation]] = [:]
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
    let continuations = state.withValue {
      $0.channels[topic] = status
      return $0.channelStatuses[topic] ?? [:]
    }
    for continuation in continuations.values { continuation.yield(status) }
  }

  /// The channel's status, starting with the current one, keeping only the newest. Registers
  /// before it returns.
  package func channelStatuses(_ topic: String) -> AsyncStream<RealtimeChannelStatus> {
    let (stream, continuation) = AsyncStream<RealtimeChannelStatus>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    let id = UUID()
    continuation.onTermination = { [weak self] _ in
      self?.state.withValue { $0.channelStatuses[topic]?[id] = nil }
    }
    state.withValue {
      // Reading the status and registering in one critical section keeps a concurrent
      // `setChannel` from being lost or reordered. Nothing iterates the stream yet, so this yield
      // runs no consumer code under the lock.
      continuation.yield($0.channels[topic] ?? .unsubscribed)
      $0.channelStatuses[topic, default: [:]][id] = continuation
    }
    return stream
  }

  func setPostgresChangeIDs(_ topic: String, _ ids: [Int]) {
    state.withValue { $0.postgresChangeIDs[topic] = ids }
  }

  func removeChannel(_ topic: String) {
    let statuses = state.withValue {
      $0.channels[topic] = nil
      $0.postgresChangeIDs[topic] = nil
      return $0.channelStatuses.removeValue(forKey: topic) ?? [:]
    }
    for continuation in statuses.values { continuation.finish() }
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
