//
//  RealtimeJoinConfig.swift
//
//
//  Created by Guilherme Souza on 24/12/23.
//

import Foundation

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
public struct ReplayOption: Encodable, Hashable, Sendable {
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
/// - ``init(acknowledgeBroadcasts:receiveOwnBroadcasts:replay:replicationReady:)``
public struct BroadcastJoinConfig: Encodable, Hashable, Sendable {
  /// When `true`, the server acknowledges each broadcast message before delivering it.
  ///
  /// Useful in combination with ``RealtimeChannel/broadcast(event:message:)-(_,JSONObject)``
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
  /// Listen for it with the ``RealtimeChannel/system()`` async stream: the message's `status` is
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
public struct PresenceJoinConfig: Encodable, Hashable, Sendable {
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

  /// Whether a change the server reports under this binding reaches a stream opened with
  /// `listener`. A listener for every event (`*`) receives a change from a binding for one event.
  package func matches(_ listener: PostgresJoinConfig) -> Bool {
    schema == listener.schema
      && table == listener.table
      && filter == listener.filter
      && (event == listener.event || listener.event == .all)
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
