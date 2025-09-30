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

/// Configuration for broadcast replay feature.
/// Allows replaying broadcast messages from a specific timestamp.
public struct ReplayOption: Codable, Hashable, Sendable {
  /// Unix timestamp (in milliseconds) from which to start replaying messages
  public var since: Int
  /// Optional limit on the number of messages to replay
  public var limit: Int?

  public init(since: Int, limit: Int? = nil) {
    self.since = since
    self.limit = limit
  }
}

public struct BroadcastJoinConfig: Codable, Hashable, Sendable {
  /// Instructs server to acknowledge that broadcast message was received.
  public var acknowledgeBroadcasts: Bool = false
  /// Broadcast messages back to the sender.
  ///
  /// By default, broadcast messages are only sent to other clients.
  public var receiveOwnBroadcasts: Bool = false
  /// Configures broadcast replay from a specific timestamp
  public var replay: ReplayOption?

  public init(
    acknowledgeBroadcasts: Bool = false,
    receiveOwnBroadcasts: Bool = false,
    replay: ReplayOption? = nil
  ) {
    self.acknowledgeBroadcasts = acknowledgeBroadcasts
    self.receiveOwnBroadcasts = receiveOwnBroadcasts
    self.replay = replay
  }

  enum CodingKeys: String, CodingKey {
    case acknowledgeBroadcasts = "ack"
    case receiveOwnBroadcasts = "self"
    case replay
  }
}

public struct PresenceJoinConfig: Codable, Hashable, Sendable {
  /// Track presence payload across clients.
  public var key: String = ""
  var enabled: Bool = false
}

public enum PostgresChangeEvent: String, Codable, Sendable {
  case insert = "INSERT"
  case update = "UPDATE"
  case delete = "DELETE"
  case all = "*"
}

struct PostgresJoinConfig: Codable, Hashable, Sendable {
  var event: PostgresChangeEvent?
  var schema: String
  var table: String?
  var filter: String?
  var id: Int = 0

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

    if id != 0 {
      try container.encode(id, forKey: .id)
    }
  }
}
