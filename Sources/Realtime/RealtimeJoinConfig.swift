//
//  RealtimeJoinConfig.swift
//
//
//  Created by Guilherme Souza on 24/12/23.
//

import Foundation

struct RealtimeJoinPayload: Encodable {
  var config: RealtimeJoinConfig
  var accessToken: String?
  var version: String?

  enum CodingKeys: String, CodingKey {
    case config
    case accessToken = "access_token"
    case version
  }
}

package struct RealtimeJoinConfig: Encodable, Hashable {
  package var broadcast: BroadcastJoinConfig = .init()
  package var presence: PresenceJoinConfig = .init()
  package var postgresChanges: [PostgresJoinConfig] = []
  package var isPrivate: Bool = false
  package var postgresChangesOptions: PostgresChangesOptions?

  package init(
    broadcast: BroadcastJoinConfig = .init(),
    presence: PresenceJoinConfig = .init(),
    postgresChanges: [PostgresJoinConfig] = [],
    isPrivate: Bool = false,
    postgresChangesOptions: PostgresChangesOptions? = nil
  ) {
    self.broadcast = broadcast
    self.presence = presence
    self.postgresChanges = postgresChanges
    self.isPrivate = isPrivate
    self.postgresChangesOptions = postgresChangesOptions
  }

  /// The join config for a channel's public configuration and its postgres bindings, in order.
  package init(_ configuration: RealtimeChannelConfiguration, bindings: [PostgresJoinConfig]) {
    self.init(
      broadcast: BroadcastJoinConfig(
        acknowledgeBroadcasts: configuration.broadcast.acknowledge,
        receiveOwnBroadcasts: configuration.broadcast.receiveOwnMessages,
        replay: configuration.broadcast.replay.map {
          ReplayOption(
            since: Int(($0.since.timeIntervalSince1970 * 1000).rounded()), limit: $0.limit)
        },
        replicationReady: configuration.broadcast.waitForReplication),
      presence: PresenceJoinConfig(key: configuration.presence.key ?? ""),
      postgresChanges: bindings,
      isPrivate: configuration.isPrivate,
      postgresChangesOptions: configuration.postgresChanges.waitForSubscription
        ? PostgresChangesOptions(
          wait: true, timeout: configuration.postgresChanges.subscriptionTimeout)
        : nil)
  }

  /// How much longer than the engine's timeout the join reply may take: the server holds it until
  /// the postgres bindings are attached when asked to wait.
  package var extraJoinTimeout: Duration {
    guard let options = postgresChangesOptions, options.wait, !postgresChanges.isEmpty else {
      return .zero
    }
    return options.timeout
  }

  enum CodingKeys: String, CodingKey {
    case broadcast
    case presence
    case isPrivate = "private"
    case postgresChanges = "postgres_changes"
    case postgresChangesOptions = "postgres_changes_options"
  }
}

/// Sent as `postgres_changes_options`.
package struct PostgresChangesOptions: Encodable, Hashable, Sendable {
  /// Sent as `wait`: the server replies to the join only once the bindings are attached.
  package var wait: Bool
  /// Not sent. How long the client gives the server to attach the bindings.
  package var timeout: Duration

  package init(wait: Bool, timeout: Duration) {
    self.wait = wait
    self.timeout = timeout
  }

  enum CodingKeys: String, CodingKey {
    case wait
  }
}

/// Options for replaying previously broadcast messages when joining a channel.
///
/// Pass a `ReplayOption` to ``BroadcastJoinConfig/replay`` to receive messages
/// that were broadcast before the client subscribed.
///
/// ## Topics
/// ### Properties
/// - ``since``
/// - ``limit``
/// ### Initialization
/// - ``init(since:limit:)``
package struct ReplayOption: Encodable, Hashable, Sendable {
  /// Unix timestamp in milliseconds. Messages broadcast after this point will be replayed.
  package var since: Int

  /// Optional maximum number of messages to replay. When `nil`, the server default limit applies.
  package var limit: Int?

  /// Creates a ``ReplayOption``.
  ///
  /// - Parameters:
  ///   - since: Unix timestamp in milliseconds from which to start replaying messages.
  ///   - limit: Maximum number of messages to replay, or `nil` for no limit.
  package init(since: Int, limit: Int? = nil) {
    self.since = since
    self.limit = limit
  }
}

/// Configuration for the broadcast feature of a Realtime channel.
///
/// Pass an instance to ``RealtimeChannelConfig/broadcast`` when creating a channel.
///
/// ## Topics
/// ### Properties
/// - ``acknowledgeBroadcasts``
/// - ``receiveOwnBroadcasts``
/// - ``replay``
/// ### Initialization
/// - ``init(acknowledgeBroadcasts:receiveOwnBroadcasts:replay:replicationReady:)``
package struct BroadcastJoinConfig: Encodable, Hashable, Sendable {
  /// Sent as `broadcast.ack`: the server acknowledges each broadcast it receives.
  package var acknowledgeBroadcasts: Bool = false

  /// When `true`, broadcast messages are echoed back to the sender in addition to all other subscribers.
  ///
  /// By default, broadcast messages are only sent to other clients.
  package var receiveOwnBroadcasts: Bool = false

  /// When set, the server replays broadcast messages starting from the given timestamp on join.
  package var replay: ReplayOption?
  /// Sent as `broadcast.replication_ready`: the server emits a `system` event once the Postgres
  /// replication connection is ready.
  package var replicationReady: Bool = false

  /// Creates a ``BroadcastJoinConfig``.
  ///
  /// - Parameters:
  ///   - acknowledgeBroadcasts: Whether the server should acknowledge each broadcast. Defaults to `false`.
  ///   - receiveOwnBroadcasts: Whether to echo broadcasts back to the sender. Defaults to `false`.
  ///   - replay: Optional replay configuration for receiving past broadcasts on join.
  package init(
    acknowledgeBroadcasts: Bool = false,
    receiveOwnBroadcasts: Bool = false,
    replay: ReplayOption? = nil,
    replicationReady: Bool = false
  ) {
    self.acknowledgeBroadcasts = acknowledgeBroadcasts
    self.receiveOwnBroadcasts = receiveOwnBroadcasts
    self.replay = replay
    self.replicationReady = replicationReady
  }

  enum CodingKeys: String, CodingKey {
    case acknowledgeBroadcasts = "ack"
    case receiveOwnBroadcasts = "self"
    case replay
    case replicationReady = "replication_ready"
  }
}

/// Configuration for the presence feature of a Realtime channel.
///
/// Pass an instance to ``RealtimeChannelConfig/presence`` when creating a channel.
///
/// ## Topics
/// ### Properties
/// - ``key``
/// ### Initialization
/// - ``init(key:)``
package struct PresenceJoinConfig: Encodable, Hashable, Sendable {
  /// The client-defined key used to identify this client's presence entry in the presence map.
  ///
  /// All clients sharing the same key are grouped together in ``PresenceAction/joins``
  /// and ``PresenceAction/leaves``. Defaults to an empty string, which lets the server
  /// assign a random unique key.
  package var key: String = ""
  var enabled: Bool = false
}

extension PresenceJoinConfig {
  /// Creates a ``PresenceJoinConfig`` with the specified key.
  ///
  /// - Parameter key: The presence key for this client. Defaults to `""`.
  package init(key: String = "") {
    self.key = key
  }
}

/// The type of Postgres change event to subscribe to.
///
/// ## Topics
/// ### Cases
/// - ``insert``
/// - ``update``
/// - ``delete``
/// - ``all``
public enum PostgresChangeEvent: String, Codable, Sendable {
  /// Subscribe to `INSERT` events only.
  case insert = "INSERT"

  /// Subscribe to `UPDATE` events only.
  case update = "UPDATE"

  /// Subscribe to `DELETE` events only.
  case delete = "DELETE"

  /// Subscribe to all change events (`INSERT`, `UPDATE`, and `DELETE`).
  case all = "*"
}

package struct PostgresJoinConfig: Codable, Hashable, Sendable {
  package var event: PostgresChangeEvent?
  package var schema: String
  package var table: String?
  package var filter: String?
  /// Restricts the change payload to a subset of columns instead of the full row.
  package var select: [String]?
  package var id: Int = 0

  package init(
    event: PostgresChangeEvent? = nil, schema: String, table: String? = nil,
    filter: String? = nil, select: [String]? = nil, id: Int = 0
  ) {
    self.event = event
    self.schema = schema
    self.table = table
    self.filter = filter
    self.select = select
    self.id = id
  }

  // `select` is excluded from `==`/`hash`: the server-echoed config used for
  // callback-id matching does not carry it.
  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.schema == rhs.schema
      && lhs.table == rhs.table
      && lhs.filter == rhs.filter
      && (lhs.event == rhs.event || rhs.event == .all)
  }

  package func hash(into hasher: inout Hasher) {
    hasher.combine(schema)
    hasher.combine(table)
    hasher.combine(filter)
    hasher.combine(event)
  }

  package func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(event, forKey: .event)
    try container.encode(schema, forKey: .schema)
    try container.encodeIfPresent(table, forKey: .table)
    try container.encodeIfPresent(filter, forKey: .filter)
    try container.encodeIfPresent(select, forKey: .select)

    if id != 0 {
      try container.encode(id, forKey: .id)
    }
  }
}
