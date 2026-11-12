//
//  PostgresActionData.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import Foundation

struct PostgresActionData: Codable, Sendable {
  var type: String
  var record: [String: AnyJSON]?
  var oldRecord: [String: AnyJSON]?
  var columns: [PostgresColumn]
  var commitTimestamp: Date
  var schema: String?
  var table: String?
  var errors: [String]?

  enum CodingKeys: String, CodingKey {
    case type
    case record
    case oldRecord = "old_record"
    case columns
    case commitTimestamp = "commit_timestamp"
    case schema
    case table
    case errors
  }
}

/// One `postgres_changes` message, as the channel hands it to its callbacks.
struct PostgresChangeDelivery: Sendable {
  var data: PostgresActionData
  var rawMessage: RealtimeMessageV2
}
