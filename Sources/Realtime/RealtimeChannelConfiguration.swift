//
//  RealtimeChannelConfiguration.swift
//  Realtime
//
//  Created by Guilherme Souza on 08/10/26.
//

public import Foundation

/// How a ``RealtimeChannel`` joins: privacy, broadcast, presence and postgres changes options.
///
/// The SDK sends these values with every join, so a change takes effect on the next subscribe.
public struct RealtimeChannelConfiguration: Sendable, Hashable {
  /// Whether the channel is private. A private channel checks the `realtime.messages` row level
  /// security policies against the caller's token on join, and on every broadcast and presence
  /// call.
  public var isPrivate = false
  /// Broadcast options.
  public var broadcast = Broadcast()
  /// Presence options.
  public var presence = Presence()
  /// Postgres changes options.
  public var postgresChanges = PostgresChanges()

  /// Creates the default configuration: a public channel, with every option off.
  public init() {}

  /// Broadcast options of a channel.
  public struct Broadcast: Sendable, Hashable {
    /// Whether the server sends this client's own broadcasts back to it.
    public var receiveOwnMessages = false
    /// Whether ``RealtimeChannel/broadcast(event:payload:encoder:)`` waits for the server to
    /// acknowledge each message.
    ///
    /// On a private channel the server does not reply when row level security denies the write,
    /// so a denied broadcast fails with a timeout.
    public var acknowledge = false
    /// Messages to replay from history on join. Private channels only: on a public channel
    /// ``RealtimeChannel/subscribe()`` throws before it joins.
    public var replay: Replay? = nil
    /// Whether the server sends a `system` message once its replication connection is ready.
    public var waitForReplication = false

    /// Which broadcast messages the server replays on join.
    public struct Replay: Sendable, Hashable {
      /// The server replays messages sent after this date.
      public var since: Date
      /// The most messages the server replays, or `nil` for the server's default.
      public var limit: Int?

      /// Creates a replay window.
      ///
      /// - Parameters:
      ///   - since: The server replays messages sent after this date.
      ///   - limit: The most messages the server replays, or `nil` for the server's default.
      public init(since: Date, limit: Int? = nil) {
        self.since = since
        self.limit = limit
      }
    }
  }

  /// Presence options of a channel.
  public struct Presence: Sendable, Hashable {
    /// The key of this client's presence entry. When `nil`, the server picks a new UUID on each
    /// join.
    public var key: String? = nil
  }

  /// Postgres changes options of a channel.
  public struct PostgresChanges: Sendable, Hashable {
    /// Whether the server holds the join reply until the postgres changes bindings are attached.
    ///
    /// When `false`, ``RealtimeChannel/subscribe()`` sends the join and then waits for the
    /// server's "Subscribed to PostgreSQL" message instead. Either way, `subscribe()` returns once
    /// changes are live.
    public var waitForSubscription = false
    /// How long ``RealtimeChannel/subscribe()`` waits for the postgres changes bindings, on top of
    /// the join timeout.
    public var subscriptionTimeout: Duration = .seconds(15)
  }
}
