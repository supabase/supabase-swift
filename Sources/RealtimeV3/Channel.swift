//
//  Channel.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

// Expanded in Task 16: state, messages(), subscribe(), leave(), broadcast(), track(), etc.

/// A Realtime channel that represents a named topic on the server.
///
/// Obtain a `Channel` by calling `Realtime.channel(_:configure:)`. The channel's
/// `topic` and `options` are immutable after creation.
public actor Channel {
  /// The Phoenix topic this channel is subscribed to (e.g. `"realtime:public:messages"`).
  public nonisolated let topic: String

  /// The options applied at channel creation. Immutable after creation (Decision 33).
  public nonisolated let options: ChannelOptions

  // Internal back-reference to the owning Realtime actor for future use (Task 16).
  // Weak ownership via unowned is not possible for actors, so we store a reference.
  // Task 16 will use this for join/leave/broadcast/presence.
  nonisolated let realtime: Realtime

  init(topic: String, options: ChannelOptions, realtime: Realtime) {
    self.topic = topic
    self.options = options
    self.realtime = realtime
  }

  /// Called by the frame router when a message arrives for this channel's topic.
  /// Expanded in Task 19.
  func receive(_ message: PhoenixMessage) {
    // Expanded in Task 19: fan-out to messages() consumers.
    _ = message
  }
}
