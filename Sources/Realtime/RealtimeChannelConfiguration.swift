//
//  RealtimeChannelConfiguration.swift
//  Realtime
//
//  Created by Guilherme Souza on 29/10/26.
//

public import Foundation

/// How a ``RealtimeChannel`` joins its topic: privacy, broadcast, presence and Postgres changes
/// options.
///
/// Set the configuration in the closure you pass to ``RealtimeClient/channel(_:configure:)``. It
/// is fixed for the life of the channel; to change it, remove the channel and create it again.
///
/// ```swift
/// let channel = await client.channel("room:lobby") { config in
///   config.isPrivate = true
///   config.broadcast.receiveOwnMessages = true
/// }
/// ```
///
/// ## Topics
/// ### Options
/// - ``isPrivate``
/// - ``broadcast-swift.property``
/// - ``presence-swift.property``
/// - ``postgresChanges-swift.property``
/// ### Option Groups
/// - ``Broadcast-swift.struct``
/// - ``Presence-swift.struct``
/// - ``PostgresChanges-swift.struct``
/// ### Initialization
/// - ``init()``
public struct RealtimeChannelConfiguration: Sendable, Hashable {
  /// Whether the channel is private.
  ///
  /// For a private channel, the server works out the caller's permissions from the
  /// `realtime.messages` row level security policies and the token when the channel joins, and
  /// checks every broadcast and presence call against them. See the
  /// [Realtime authorization guide](https://supabase.com/docs/guides/realtime/authorization).
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
    /// Whether the server sends this client's own broadcasts back to it. Defaults to `false`.
    public var receiveOwnMessages = false

    /// Whether ``RealtimeChannel/broadcast(event:payload:encoder:)`` waits for the server to
    /// acknowledge each message. Defaults to `false`.
    ///
    /// On a private channel the server does not reply when row level security denies the write,
    /// so a denied broadcast fails with a timeout.
    public var acknowledge = false

    /// The messages the server replays from history when the channel joins. Private channels
    /// only. Defaults to `nil`, which replays nothing.
    public var replay: Replay?

    /// Whether the server sends a `system` message once its replication connection is ready.
    ///
    /// Listen for it with ``RealtimeChannel/events()``: it emits
    /// ``RealtimeChannelEvent/replicationReady``, or ``RealtimeChannelEvent/replicationFailed(_:)``
    /// when the connection is not ready in time. Defaults to `false`.
    public var waitForReplication = false

    /// Creates broadcast options with every option off.
    public init() {}

    /// Which broadcast messages the server replays when the channel joins.
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
    /// The key of this client's presence entry.
    ///
    /// Clients that share a key are grouped under it in ``PresenceState/entries``, one
    /// ``PresenceEntry`` per connection. When `nil`, the server picks a new key on each join.
    public var key: String?

    /// Creates presence options with no key.
    public init() {}
  }

  /// Postgres changes options of a channel.
  public struct PostgresChanges: Sendable, Hashable {
    /// Whether the server holds the join reply until the channel's Postgres changes bindings are
    /// set up. Defaults to `false`.
    ///
    /// Either way, ``RealtimeChannel/subscribe()`` returns only once changes are live. When
    /// `true`, the server waits before it replies to the join, and the join timeout grows by
    /// ``subscriptionTimeout``. When `false`, the server replies at once and the SDK then waits
    /// for the server's "Subscribed to PostgreSQL" message.
    public var waitForSubscription = false

    /// How long ``RealtimeChannel/subscribe()`` waits for the Postgres changes bindings to be set
    /// up, after the join itself. Defaults to 15 seconds.
    ///
    /// When ``waitForSubscription`` is on, the server caps this value.
    public var subscriptionTimeout: Duration = .seconds(15)

    /// Creates Postgres changes options with the defaults.
    public init() {}
  }
}
