//
//  EngineMirror.swift
//  Realtime
//
//  Created by Guilherme Souza on 08/10/26.
//

import ConcurrencyExtras
package import Foundation

/// Lock-protected state the engine writes and public handles read synchronously.
///
/// Channel state and listeners belong to one handle, its owner id. A topic has at most one live
/// owner, the owner of the engine's record; reads from any other owner see an unsubscribed,
/// empty channel, and fan-out reaches only the live owner's listeners. A handle's listeners can
/// register before its record exists and start receiving once it is installed.
///
/// Never yield or call out while holding the lock: copy what is needed out first.
package final class EngineMirror: Sendable {
  private struct Key: Hashable {
    var topic: String
    var owner: UUID
  }

  private struct State {
    var connection: RealtimeConnectionStatus = .disconnected(nil)
    var connectionStatuses: [UUID: AsyncStream<RealtimeConnectionStatus>.Continuation] = [:]
    var owners: [String: UUID] = [:]
    var channels: [String: RealtimeChannelStatus] = [:]
    var channelStatuses: [Key: [UUID: AsyncStream<RealtimeChannelStatus>.Continuation]] = [:]
    var postgresChangeIDs: [String: [Int]] = [:]
    var presence: [String: PresenceState] = [:]
    var heartbeats: [UUID: AsyncStream<HeartbeatEvent>.Continuation] = [:]
    var inbound: [Key: [UUID: AsyncStream<ChannelInbound>.Continuation]] = [:]
    /// Set by ``EngineMirror/shutDown()``: every stream is finished, and a new one finishes at once.
    var isShutDown = false

    func isLive(_ topic: String, _ owner: UUID) -> Bool { owners[topic] == owner }

    func liveKey(_ topic: String) -> Key? {
      owners[topic].map { Key(topic: topic, owner: $0) }
    }
  }

  private let state = LockIsolated(State())

  package init() {}

  package var connection: RealtimeConnectionStatus { state.connection }

  /// Makes `owner` the live owner of `topic`, for a record the engine just created.
  package func install(_ topic: String, owner: UUID) {
    state.withValue { $0.owners[topic] = owner }
  }

  /// `.unsubscribed` unless `owner` holds the topic's live record.
  package func channel(_ topic: String, owner: UUID) -> RealtimeChannelStatus {
    state.withValue {
      $0.isLive(topic, owner) ? $0.channels[topic] ?? .unsubscribed : .unsubscribed
    }
  }

  package func postgresChangeIDs(_ topic: String) -> [Int] {
    state.postgresChangeIDs[topic] ?? []
  }

  /// Empty unless `owner` holds the topic's live record.
  package func presence(_ topic: String, owner: UUID) -> PresenceState {
    state.withValue {
      $0.isLive(topic, owner) ? $0.presence[topic] ?? PresenceState() : PresenceState()
    }
  }

  func setPresence(_ topic: String, _ presence: PresenceState) {
    state.withValue { $0.presence[topic] = presence }
  }
  func setConnection(_ status: RealtimeConnectionStatus) {
    let continuations = state.withValue {
      $0.connection = status
      return $0.connectionStatuses
    }
    for continuation in continuations.values { continuation.yield(status) }
  }

  /// The socket's status, starting with the current one, keeping only the newest. Registers
  /// before it returns.
  package func connectionStatuses() -> AsyncStream<RealtimeConnectionStatus> {
    let (stream, continuation) = AsyncStream<RealtimeConnectionStatus>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    let id = UUID()
    continuation.onTermination = { [weak self] _ in
      self?.state.withValue { $0.connectionStatuses[id] = nil }
    }
    state.withValue {
      // Same single critical section as `channelStatuses(_:)`, for the same reason.
      guard !$0.isShutDown else {
        continuation.yield(.disconnected(nil))
        continuation.finish()
        return
      }
      continuation.yield($0.connection)
      $0.connectionStatuses[id] = continuation
    }
    return stream
  }

  func setChannel(_ topic: String, _ status: RealtimeChannelStatus) {
    let continuations = state.withValue { state in
      state.channels[topic] = status
      return state.liveKey(topic).flatMap { state.channelStatuses[$0] } ?? [:]
    }
    for continuation in continuations.values { continuation.yield(status) }
  }

  /// The channel's status, starting with the current one, keeping only the newest. Registers
  /// before it returns. For a retired owner, or after shutdown, it yields `.unsubscribed` and
  /// ends.
  package func channelStatuses(_ topic: String, owner: ChannelOwner)
    -> AsyncStream<RealtimeChannelStatus>
  {
    let (stream, continuation) = AsyncStream<RealtimeChannelStatus>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    let key = Key(topic: topic, owner: owner.id)
    let id = UUID()
    continuation.onTermination = { [weak self] _ in
      self?.state.withValue { $0.channelStatuses[key]?[id] = nil }
    }
    state.withValue {
      // Reading the status and registering in one critical section keeps a concurrent
      // `setChannel` or `removeChannel` from being lost or reordered. Nothing iterates the stream
      // yet, so this yield runs no consumer code under the lock.
      guard !$0.isShutDown, !owner.isRetired else {
        continuation.yield(.unsubscribed)
        continuation.finish()
        return
      }
      continuation.yield(
        $0.isLive(topic, owner.id) ? $0.channels[topic] ?? .unsubscribed : .unsubscribed)
      $0.channelStatuses[key, default: [:]][id] = continuation
    }
    return stream
  }

  func setPostgresChangeIDs(_ topic: String, _ ids: [Int]) {
    state.withValue { $0.postgresChangeIDs[topic] = ids }
  }

  /// Forgets the topic's state when `owner` holds it, and finishes every stream of `owner`.
  func removeChannel(_ topic: String, owner: UUID) {
    let key = Key(topic: topic, owner: owner)
    let (statuses, inbound) = state.withValue { state in
      if state.isLive(topic, owner) {
        state.owners[topic] = nil
        state.channels[topic] = nil
        state.postgresChangeIDs[topic] = nil
        state.presence[topic] = nil
      }
      return (
        state.channelStatuses.removeValue(forKey: key) ?? [:],
        state.inbound.removeValue(forKey: key) ?? [:]
      )
    }
    for continuation in statuses.values { continuation.finish() }
    for continuation in inbound.values { continuation.finish() }
  }

  func heartbeats() -> AsyncStream<HeartbeatEvent> {
    let (stream, continuation) = AsyncStream<HeartbeatEvent>.makeStream(
      bufferingPolicy: .unbounded)
    let id = UUID()
    continuation.onTermination = { [weak self] _ in
      self?.state.withValue { $0.heartbeats[id] = nil }
    }
    state.withValue {
      if $0.isShutDown { continuation.finish() } else { $0.heartbeats[id] = continuation }
    }
    return stream
  }

  func yieldHeartbeat(_ event: HeartbeatEvent) {
    for continuation in state.heartbeats.values { continuation.yield(event) }
  }

  /// Every message `owner` receives on the topic, unbounded. Registers before it returns; ending
  /// the iteration removes the listener. For a retired owner, or after shutdown, it ends at once.
  package func inbound(_ topic: String, owner: ChannelOwner) -> AsyncStream<ChannelInbound> {
    let (stream, continuation) = AsyncStream<ChannelInbound>.makeStream(
      bufferingPolicy: .unbounded)
    let key = Key(topic: topic, owner: owner.id)
    let id = UUID()
    continuation.onTermination = { [weak self] _ in
      self?.removeInbound(id, from: key)
    }
    state.withValue {
      // Checked under the lock, so it orders with `removeChannel`, which runs after `retire()`.
      if $0.isShutDown || owner.isRetired {
        continuation.finish()
      } else {
        $0.inbound[key, default: [:]][id] = continuation
      }
    }
    return stream
  }

  /// The live owner's listeners on the topic.
  package func listenerCount(_ topic: String) -> Int {
    state.withValue { state in state.liveKey(topic).flatMap { state.inbound[$0]?.count } ?? 0 }
  }

  package func yield(_ value: ChannelInbound, to topic: String) {
    let continuations = state.withValue { state in
      state.liveKey(topic).flatMap { state.inbound[$0] } ?? [:]
    }
    for continuation in continuations.values { continuation.yield(value) }
  }

  /// Finishes the live owner's data streams on the topic.
  package func finishInbound(_ topic: String) {
    let continuations = state.withValue { state in
      state.liveKey(topic).flatMap { state.inbound.removeValue(forKey: $0) } ?? [:]
    }
    for continuation in continuations.values { continuation.finish() }
  }

  /// Finishes every stream, after a last `.disconnected` or `.unsubscribed` on status streams,
  /// and makes every later stream end at once.
  func shutDown() {
    let (connections, channels, heartbeats, inbound) = state.withValue { state in
      state.isShutDown = true
      defer {
        state.connectionStatuses = [:]
        state.channelStatuses = [:]
        state.heartbeats = [:]
        state.inbound = [:]
      }
      return (
        state.connectionStatuses.values, state.channelStatuses.values.flatMap(\.values),
        state.heartbeats.values, state.inbound.values.flatMap(\.values)
      )
    }
    for continuation in connections {
      continuation.yield(.disconnected(nil))
      continuation.finish()
    }
    for continuation in channels {
      continuation.yield(.unsubscribed)
      continuation.finish()
    }
    heartbeats.forEach { $0.finish() }
    inbound.forEach { $0.finish() }
  }

  private func removeInbound(_ id: UUID, from key: Key) {
    state.withValue { state in
      state.inbound[key]?[id] = nil
      if state.inbound[key]?.isEmpty == true { state.inbound[key] = nil }
    }
  }
}
