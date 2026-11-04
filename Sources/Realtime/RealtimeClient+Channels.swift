//
//  RealtimeClient+Channels.swift
//  Realtime
//

import Foundation
import Helpers
import IssueReporting

/// What ``RealtimeChannel`` forwards to its client, one actor hop per call. The client owns every
/// channel's state, so a read, a new stream, or an action sees the state the last batch left.
extension RealtimeClient {
  /// The state of `channel`, or `nil` when it is spent or another client created it.
  func state(of channel: RealtimeChannel) -> ChannelState? {
    guard let state = channelStates[channel.id], state.handle === channel else { return nil }
    return state
  }

  // MARK: Reads

  /// The status of `channel`. A spent channel reads ``RealtimeChannelStatus/unsubscribed``.
  func channelStatus(_ channel: RealtimeChannel) -> RealtimeChannelStatus {
    state(of: channel)?.status.current ?? .unsubscribed
  }

  /// The presence state of `channel`. A spent channel reads an empty state.
  func presenceState(of channel: RealtimeChannel) -> PresenceState {
    state(of: channel)?.presenceStates.current ?? PresenceState()
  }

  // MARK: Streams

  /// The streams below are registered before they return. A spent channel gets a stream that
  /// ends at once.
  func statusChanges(of channel: RealtimeChannel) -> AsyncStream<RealtimeChannelStatus> {
    openStream(of: channel, \.status)
  }

  func events(of channel: RealtimeChannel) -> AsyncStream<RealtimeChannelEvent> {
    openStream(of: channel, \.events)
  }

  func broadcasts(
    of channel: RealtimeChannel, event: String
  ) -> AsyncStream<BroadcastMessage> {
    openStream(of: channel, \.broadcasts, where: { RealtimeChannel.eventMatches(event, $0.event) })
  }

  func presenceChanges(of channel: RealtimeChannel) -> AsyncStream<PresenceChange> {
    openStream(of: channel, \.presenceChanges, if: canOpenPresenceStream(on:))
  }

  func presenceStates(of channel: RealtimeChannel) -> AsyncStream<PresenceState> {
    openStream(of: channel, \.presenceStates, if: canOpenPresenceStream(on:))
  }

  /// Subscribes a new stream to the fan-out `fanout` of `channel`'s state, when the channel is
  /// not spent and `condition` holds.
  private func openStream<Element: Sendable>(
    of channel: RealtimeChannel,
    _ fanout: KeyPath<ChannelState, Fanout<Element>>,
    if condition: (ChannelState) -> Bool = { _ in true },
    where filter: ((Element) -> Bool)? = nil
  ) -> AsyncStream<Element> {
    guard let state = state(of: channel), condition(state) else { return .finished }
    let id = nextStreamID(channel: channel.id)
    return state[keyPath: fanout].subscribe(id, where: filter, onTermination: onStreamEnd(id))
  }

  /// Registers the binding and hands the core the new join payload in the same actor job, so a
  /// join in flight or a subscribed channel learns of it before any later event.
  func postgresChanges(
    of channel: RealtimeChannel, _ config: PostgresJoinConfig
  ) -> AsyncStream<PostgresChange> {
    guard let state = state(of: channel) else { return .finished }
    let id = nextStreamID(channel: channel.id)
    let stream = state.addPostgresStream(id, config, onTermination: onStreamEnd(id))
    apply(.bindingsChanged(channel: channel.id, snapshot: state.joinSnapshot))
    return stream
  }

  /// Registers `bindings` like ``postgresChanges(of:_:)`` does, for one stream that also carries
  /// the channel's events and status changes in order.
  func postgresChangesSignals(
    of channel: RealtimeChannel, _ bindings: [PostgresJoinConfig]
  ) -> AsyncStream<PostgresChangesSignal> {
    guard let state = state(of: channel) else { return .finished }
    let id = nextStreamID(channel: channel.id)
    let stream = state.addSignalsStream(id, bindings, onTermination: onStreamEnd(id))
    apply(.bindingsChanged(channel: channel.id, snapshot: state.joinSnapshot))
    return stream
  }

  /// Presence streams shape the join payload, so they can only be opened before the join is sent.
  private func canOpenPresenceStream(on state: ChannelState) -> Bool {
    switch state.status.current ?? .unsubscribed {
    case .unsubscribed, .unsubscribing, .failed:
      return true
    case .subscribing, .resubscribing, .subscribed:
      reportIssue(
        """
        Cannot open "presence" streams for "\(state.handle.topic)" after `subscribe()`.
        Please open all your presence streams before subscribing to the channel.
        """
      )
      return false
    }
  }

  // MARK: Actions

  /// Joins `channel`. The join payload is read here, in the same actor job that applies the
  /// event, so it carries every stream opened before the call.
  func subscribe(_ channel: RealtimeChannel) async throws {
    guard let state = state(of: channel) else { throw RealtimeError.channelRemoved }
    let snapshot = state.joinSnapshot
    try await wait {
      [id = channel.id, topic = channel.topic, configuration = channel.configuration] waiter in
      .subscribe(
        channel: id, topic: topic, configuration: configuration, waiter: waiter,
        snapshot: snapshot)
    }
  }

  /// Leaves `channel`. Returns at once when it is spent.
  func unsubscribe(_ channel: RealtimeChannel) async {
    try? await wait(on: channel, evenIfCancelled: true) { [id = channel.id] in
      .unsubscribe(channel: id, waiter: $0)
    }
  }

  func broadcast(
    _ channel: RealtimeChannel, event: String, payload: BroadcastPushPayload
  ) async throws {
    try await wait(on: channel) { [id = channel.id] in
      .broadcast(channel: id, event: event, payload: payload, waiter: $0)
    }
  }

  func push(_ channel: RealtimeChannel, event: String, payload: JSONObject) async throws {
    try await wait(on: channel) { [id = channel.id] in
      .push(channel: id, event: event, payload: payload, waiter: $0)
    }
  }

  /// Throws ``RealtimeError/Kind-swift.struct/channelRemoved`` when `channel` is spent, for the
  /// actions that do not go through the core.
  func checkUsable(_ channel: RealtimeChannel) throws(RealtimeError) {
    guard state(of: channel) != nil else { throw .channelRemoved }
  }
}
