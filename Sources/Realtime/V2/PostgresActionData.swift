//
//  PostgresActionData.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import Foundation
import Helpers

struct PostgresActionData: Codable {
  var type: String
  var record: [String: AnyJSON]?
  var oldRecord: [String: AnyJSON]?
  var columns: [Column]
  var commitTimestamp: Date

  enum CodingKeys: String, CodingKey {
    case type
    case record
    case oldRecord = "old_record"
    case columns
    case commitTimestamp = "commit_timestamp"
  }
}
