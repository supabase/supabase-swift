//
//  RealtimeJoinConfig.swift
//
//
//  Created by Guilherme Souza on 24/12/23.
//

import Foundation

struct RealtimeJoinPayload: Codable {
  var config: RealtimeJoinConfig
  var accessToken: String?
  var version: String?

  enum CodingKeys: String, CodingKey {
    case config
    case accessToken = "access_token"
    case version
  }
}

struct RealtimeJoinConfig: Codable, Hashable {
  var broadcast: BroadcastJoinConfig = .init()
  var presence: PresenceJoinConfig = .init()
  var postgresChanges: [PostgresJoinConfig] = []
  var isPrivate: Bool = false

  enum CodingKeys: String, CodingKey {
    case broadcast
    case presence
    case isPrivate = "private"
    case postgresChanges = "postgres_changes"
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
public struct ReplayOption: Codable, Hashable, Sendable {
  /// Unix timestamp in milliseconds. Messages broadcast after this point will be replayed.
  public var since: Int

  /// Optional maximum number of messages to replay. When `nil`, the server default limit applies.
  public var limit: Int?

  /// Creates a ``ReplayOption``.
  ///
  /// - Parameters:
  ///   - since: Unix timestamp in milliseconds from which to start replaying messages.
  ///   - limit: Maximum number of messages to replay, or `nil` for no limit.
  public init(since: Int, limit: Int? = nil) {
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
/// - ``init(acknowledgeBroadcasts:receiveOwnBroadcasts:replay:)``
public struct BroadcastJoinConfig: Codable, Hashable, Sendable {
  /// When `true`, the server acknowledges each broadcast message before delivering it.
  ///
  /// Useful in combination with ``RealtimeChannelV2/broadcast(event:message:)-2pvzp``
  /// to ensure delivery before continuing.
  public var acknowledgeBroadcasts: Bool = false

  /// When `true`, broadcast messages are echoed back to the sender in addition to all other subscribers.
  ///
  /// By default, broadcast messages are only sent to other clients.
  public var receiveOwnBroadcasts: Bool = false

  /// When set, the server replays broadcast messages starting from the given timestamp on join.
  public var replay: ReplayOption?
  /// Instructs the server to emit a `system` event once the Postgres replication
  /// connection backing this channel is established and ready to stream changes.
  ///
  /// Listen for it with ``RealtimeChannelV2/onSystem(callback:)-(_)`` (or the
  /// ``RealtimeChannelV2/system()`` async stream): the message's `status` is
  /// `.ok` (message `"Replication connection established"`) on success, or
  /// `.error` if the connection is not ready in time.
  public var replicationReady: Bool = false

  /// Creates a ``BroadcastJoinConfig``.
  ///
  /// - Parameters:
  ///   - acknowledgeBroadcasts: Whether the server should acknowledge each broadcast. Defaults to `false`.
  ///   - receiveOwnBroadcasts: Whether to echo broadcasts back to the sender. Defaults to `false`.
  ///   - replay: Optional replay configuration for receiving past broadcasts on join.
  public init(
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
public struct PresenceJoinConfig: Codable, Hashable, Sendable {
  /// The client-defined key used to identify this client's presence entry in the presence map.
  ///
  /// All clients sharing the same key are grouped together in ``PresenceAction/joins``
  /// and ``PresenceAction/leaves``. Defaults to an empty string, which lets the server
  /// assign a random unique key.
  public var key: String = ""
  var enabled: Bool = false
}

extension PresenceJoinConfig {
  /// Creates a ``PresenceJoinConfig`` with the specified key.
  ///
  /// - Parameter key: The presence key for this client. Defaults to `""`.
  public init(key: String = "") {
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

struct PostgresJoinConfig: Codable, Hashable, Sendable {
  var event: PostgresChangeEvent?
  var schema: String
  var table: String?
  var filter: String?
  /// Restricts the change payload to a subset of columns instead of the full row.
  var select: [String]?
  var id: Int = 0

  // `select` is excluded from `==`/`hash`: the server-echoed config used for
  // callback-id matching does not carry it.
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.schema == rhs.schema
      && lhs.table == rhs.table
      && lhs.filter == rhs.filter
      && (lhs.event == rhs.event || rhs.event == .all)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(schema)
    hasher.combine(table)
    hasher.combine(filter)
    hasher.combine(event)
  }

  func encode(to encoder: any Encoder) throws {
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
