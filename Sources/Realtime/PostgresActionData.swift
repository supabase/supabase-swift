//
//  PostgresActionData.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import Foundation
@_spi(Internal) import _Helpers

struct PostgresActionData: Codable {
  var type: String
  var record: [String: AnyJSON]?
  var oldRecord: [String: AnyJSON]?
  var columns: [Column]
  var commitTimestamp: TimeInterval

  enum CodingKeys: String, CodingKey {
    case type
    case record
    case oldRecord = "old_record"
    case columns
    case commitTimestamp = "commit_timestamp"
  }
}
