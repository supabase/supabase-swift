//
//  RealtimeJoinPayload.swift
//
//
//  Created by Guilherme Souza on 24/12/23.
//

import Foundation

struct RealtimeJoinPayload: Codable, Hashable {
  var config: RealtimeJoinConfig
}

struct RealtimeJoinConfig: Codable, Hashable {
  var broadcast: BroadcastJoinConfig
  var presence: PresenceJoinConfig
  var postgresChanges: PostgresJoinConfig

  enum CodingKeys: String, CodingKey {
    case broadcast
    case presence
    case postgresChanges = "postgres_changes"
  }
}

struct BroadcastJoinConfig: Codable, Hashable {
  var acknowledgeBroadcasts: Bool
  var receiveOwnBroadcasts: Bool

  enum CodingKeys: String, CodingKey {
    case acknowledgeBroadcasts = "ack"
    case receiveOwnBroadcasts = "self"
  }
}

struct PresenceJoinConfig: Codable, Hashable {
  var key: String
}

struct PostgresJoinConfig: Codable, Hashable {
  var schema: String
  var table: String?
  var filter: String?
  var event: String
  var id: Int = 0

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.schema == rhs.schema && lhs.table == rhs.table && lhs.filter == rhs
      .filter && (lhs.event == rhs.event || rhs.event == "*")
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(schema)
    hasher.combine(table)
    hasher.combine(filter)
    hasher.combine(event)
  }
}
