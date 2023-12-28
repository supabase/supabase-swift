//
//  PostgresAction.swift
//
//
//  Created by Guilherme Souza on 23/12/23.
//

import Foundation
@_spi(Internal) import _Helpers

public struct Column: Equatable, Codable, Sendable {
  public let name: String
  public let type: String
}

public struct PostgresAction: Equatable, Sendable {
  public let columns: [Column]
  public let commitTimestamp: TimeInterval
  public let action: Action

  public enum Action: Equatable, Sendable {
    case insert(record: [String: AnyJSON])
    case update(record: [String: AnyJSON], oldRecord: [String: AnyJSON])
    case delete(oldRecord: [String: AnyJSON])
    case select(record: [String: AnyJSON])
  }
}
