//
//  RealtimeJoinConfig.swift
//
//
//  Created by Guilherme Souza on 24/12/23.
//

package import Foundation

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

/// The `config` object of a `phx_join` payload.
package struct RealtimeJoinConfig: Encodable, Hashable {
  package var broadcast: BroadcastJoinConfig = .init()
  package var presence: PresenceJoinConfig = .init()
  package var postgresChanges: [PostgresJoinConfig] = []
  package var postgresChangesOptions: PostgresChangesOptions?
  package var isPrivate: Bool = false

  package init(
    broadcast: BroadcastJoinConfig = .init(),
    presence: PresenceJoinConfig = .init(),
    postgresChanges: [PostgresJoinConfig] = [],
    postgresChangesOptions: PostgresChangesOptions? = nil,
    isPrivate: Bool = false
  ) {
    self.broadcast = broadcast
    self.presence = presence
    self.postgresChanges = postgresChanges
    self.postgresChangesOptions = postgresChangesOptions
    self.isPrivate = isPrivate
  }

  /// The join config for a channel's configuration, its open `postgres_changes` bindings in
  /// order, and whether presence is on.
  package init(
    _ configuration: RealtimeChannelConfiguration,
    bindings: [PostgresJoinConfig],
    presenceEnabled: Bool
  ) {
    let postgresChanges = configuration.postgresChanges
    self.init(
      broadcast: BroadcastJoinConfig(
        acknowledgeBroadcasts: configuration.broadcast.acknowledge,
        receiveOwnBroadcasts: configuration.broadcast.receiveOwnMessages,
        replay: configuration.broadcast.replay.map {
          ReplayOption(
            since: Int(($0.since.timeIntervalSince1970 * 1000).rounded()), limit: $0.limit)
        },
        replicationReady: configuration.broadcast.waitForReplication
      ),
      presence: PresenceJoinConfig(key: configuration.presence.key ?? "", enabled: presenceEnabled),
      postgresChanges: bindings,
      postgresChangesOptions: postgresChanges.waitForSubscription
        ? PostgresChangesOptions(wait: true, timeout: postgresChanges.subscriptionTimeout) : nil,
      isPrivate: configuration.isPrivate
    )
  }

  /// How much longer than the client's timeout the join reply may take: with
  /// `postgres_changes_options.wait`, the server holds the reply until the bindings are set up.
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

/// The `postgres_changes_options` object of a join config.
package struct PostgresChangesOptions: Encodable, Hashable, Sendable {
  /// The server replies to the join only once the bindings are set up.
  package var wait: Bool
  /// How long the server may hold the reply. Sent in milliseconds.
  package var timeout: Duration

  package init(wait: Bool, timeout: Duration) {
    self.wait = wait
    self.timeout = timeout
  }

  enum CodingKeys: String, CodingKey {
    case wait
    case timeout
  }

  package func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(wait, forKey: .wait)
    let (seconds, attoseconds) = timeout.components
    try container.encode(seconds * 1000 + attoseconds / 1_000_000_000_000_000, forKey: .timeout)
  }
}

/// The `broadcast.replay` object of a join config. `since` is in Unix milliseconds.
package struct ReplayOption: Encodable, Hashable, Sendable {
  package var since: Int
  package var limit: Int?

  package init(since: Int, limit: Int? = nil) {
    self.since = since
    self.limit = limit
  }
}

/// The `broadcast` object of a join config.
package struct BroadcastJoinConfig: Encodable, Hashable, Sendable {
  package var acknowledgeBroadcasts: Bool = false
  package var receiveOwnBroadcasts: Bool = false
  package var replay: ReplayOption?
  package var replicationReady: Bool = false

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

/// The `presence` object of a join config. An empty `key` lets the server pick one.
package struct PresenceJoinConfig: Encodable, Hashable, Sendable {
  package var key: String = ""
  package var enabled: Bool = false

  package init(key: String = "", enabled: Bool = false) {
    self.key = key
    self.enabled = enabled
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
