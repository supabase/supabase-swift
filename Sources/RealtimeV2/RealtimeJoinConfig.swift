//
//  RealtimeJoinConfig.swift
//
//
//  Created by Guilherme Souza on 24/12/23.
//

public import Foundation

// cspell:ignore pvzp
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
/// - ``init(since:limit:)-(Date,_)``
/// - ``init(since:limit:)-(Int,_)``
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
  @available(*, deprecated, message: "Use init(since: Date, limit:) instead.")
  public init(since: Int, limit: Int? = nil) {
    self.since = since
    self.limit = limit
  }

  /// Creates a replay window.
  ///
  /// - Parameters:
  ///   - since: The server replays messages sent after this date.
  ///   - limit: The most messages the server replays, or `nil` for the server's default.
  ///
  /// > Note: On this version ``since`` stays an `Int` of milliseconds. v3 stores the `Date`.
  public init(since: Date, limit: Int? = nil) {
    self.since = Int((since.timeIntervalSince1970 * 1000).rounded())
    self.limit = limit
  }
}

/// Configuration for the broadcast feature of a Realtime channel.
///
/// Pass an instance to ``RealtimeChannelConfig/broadcast-swift.property`` when creating a
/// channel. ``RealtimeChannelConfig/Broadcast-swift.typealias`` is the v3 name of this
/// type.
///
/// ## Topics
/// ### Properties
/// - ``acknowledgesMessages``
/// - ``receivesOwnMessages``
/// - ``replay``
/// - ``waitsForReplication``
/// ### Initialization
/// - ``init(acknowledgeBroadcasts:receiveOwnBroadcasts:replay:replicationReady:)``
public struct BroadcastJoinConfig: Codable, Hashable, Sendable {
  /// Which broadcast messages the server replays when the channel joins.
  public typealias Replay = ReplayOption

  /// Whether the server acknowledges each broadcast message. Defaults to `false`.
  public var acknowledgesMessages: Bool = false

  /// Whether the server sends this client's own broadcasts back to it. Defaults to `false`.
  public var receivesOwnMessages: Bool = false

  /// When set, the server replays broadcast messages starting from the given timestamp on join.
  public var replay: ReplayOption?

  /// Whether the server sends a `system` message once the Postgres replication connection behind
  /// the channel is ready. Defaults to `false`.
  ///
  /// The message's `status` is `.ok` (message `"Replication connection established"`) on
  /// success, or `.error` if the connection is not ready in time.
  public var waitsForReplication: Bool = false

  /// When `true`, the server acknowledges each broadcast message before delivering it.
  @available(*, deprecated, message: "Use acknowledgesMessages instead.")
  public var acknowledgeBroadcasts: Bool {
    get { acknowledgesMessages }
    set { acknowledgesMessages = newValue }
  }

  /// When `true`, broadcast messages are echoed back to the sender in addition to all other subscribers.
  @available(*, deprecated, message: "Use receivesOwnMessages instead.")
  public var receiveOwnBroadcasts: Bool {
    get { receivesOwnMessages }
    set { receivesOwnMessages = newValue }
  }

  /// Instructs the server to emit a `system` event once the Postgres replication
  /// connection backing this channel is established and ready to stream changes.
  @available(*, deprecated, message: "Use waitsForReplication instead.")
  public var replicationReady: Bool {
    get { waitsForReplication }
    set { waitsForReplication = newValue }
  }

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
    self.acknowledgesMessages = acknowledgeBroadcasts
    self.receivesOwnMessages = receiveOwnBroadcasts
    self.replay = replay
    self.waitsForReplication = replicationReady
  }

  enum CodingKeys: String, CodingKey {
    case acknowledgesMessages = "ack"
    case receivesOwnMessages = "self"
    case replay
    case waitsForReplication = "replication_ready"
  }
}

/// Configuration for the presence feature of a Realtime channel.
///
/// Pass an instance to ``RealtimeChannelConfig/presence-swift.property`` when creating a
/// channel. ``RealtimeChannelConfig/Presence-swift.typealias`` is the v3 name of this type.
///
/// ## Topics
/// ### Properties
/// - ``key``
/// - ``isEnabled``
/// ### Initialization
/// - ``init(key:)``
public struct PresenceJoinConfig: Codable, Hashable, Sendable {
  /// The client-defined key used to identify this client's presence entry in the presence map.
  ///
  /// All clients sharing the same key are grouped together in ``PresenceAction/joins``
  /// and ``PresenceAction/leaves``. Defaults to an empty string, which lets the server
  /// assign a random unique key.
  public var key: String = ""

  /// Whether the channel joins with presence on.
  ///
  /// A presence stream that is open when the channel subscribes turns presence on by itself.
  /// Set this to `true` to turn it on with no stream, for example to read
  /// ``RealtimeChannelV2/presenceState`` only. Defaults to `false`.
  public var isEnabled = false

  /// What the join sends: ``isEnabled``, or a presence stream or callback on the channel.
  var enabled: Bool = false

  enum CodingKeys: String, CodingKey {
    case key
    case enabled
  }
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
