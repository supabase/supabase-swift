//
//  ChannelOptions.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation

// MARK: - ChannelOptions

/// Options applied at channel creation time. Options are locked on the first `channel(_:configure:)`
/// call — subsequent calls for the same topic with different options are ignored and a debug warning
/// is emitted (Decision 33: first-call-wins).
public struct ChannelOptions: Sendable {
  /// Whether the channel is a private channel. Private channels require a valid JWT and support
  /// backend replay.
  public var isPrivate: Bool = false

  /// Broadcast behaviour options.
  public var broadcast: BroadcastOptions = .init()

  /// Presence behaviour options.
  public var presence: PresenceOptions = .init()

  public init() {}
}

// MARK: - BroadcastOptions

/// Options controlling broadcast behaviour for a channel.
public struct BroadcastOptions: Sendable {
  /// When `true`, `broadcast()` calls wait for a server acknowledgement before returning.
  /// Default: `false` (fire-and-forget).
  public var acknowledge: Bool = false

  /// When `true`, the client receives its own broadcast messages. Default: `false`.
  public var receiveOwnBroadcasts: Bool = false

  /// Backend replay configuration. Only valid on private channels (`isPrivate == true`).
  /// Public-channel replay is rejected by the backend. Default: `nil` (no replay).
  public var replay: ReplayOption? = nil

  public init() {}
}

// MARK: - ReplayOption

/// Configures backend replay for a private broadcast channel.
public struct ReplayOption: Sendable {
  /// Replay messages sent at or after this date.
  public var since: Date

  /// Maximum number of messages to replay. Clamped server-side to 1...25, defaulting to 25
  /// when `nil`.
  public var limit: Int?

  public init(since: Date, limit: Int? = nil) {
    self.since = since
    self.limit = limit
  }
}

// MARK: - PresenceOptions

/// Options controlling presence behaviour for a channel.
public struct PresenceOptions: Sendable {
  /// Sends `presence.enabled = true` in the join config. Required for an initial
  /// `presence_state` snapshot on join. If `false`, `track` can still create/update presence
  /// later, but observers cannot retroactively get the initial snapshot.
  public var enabled: Bool = false

  /// Presence key for this channel process. If `nil` or empty, the server generates a fresh
  /// UUID per join.
  public var key: String? = nil

  public init() {}
}
