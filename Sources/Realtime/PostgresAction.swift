//
//  PostgresAction.swift
//
//
//  Created by Guilherme Souza on 23/12/23.
//

import Foundation
import Helpers

public struct Column: Equatable, Codable, Sendable {
  public let name: String
  public let type: String
}

public protocol PostgresAction: Equatable, Sendable {
  static var eventType: PostgresChangeEvent { get }
}

public protocol HasRecord {
  var record: JSONObject { get }
}

public protocol HasOldRecord {
  var oldRecord: JSONObject { get }
}

public protocol HasRawMessage {
  var rawMessage: RealtimeMessage { get }
}

public struct InsertAction: PostgresAction, HasRecord, HasRawMessage {
  public static let eventType: PostgresChangeEvent = .insert

  public let columns: [Column]
  public let commitTimestamp: Date
  public let record: [String: AnyJSON]
  public let rawMessage: RealtimeMessage
}

public struct UpdateAction: PostgresAction, HasRecord, HasOldRecord, HasRawMessage {
  public static let eventType: PostgresChangeEvent = .update

  public let columns: [Column]
  public let commitTimestamp: Date
  public let record, oldRecord: [String: AnyJSON]
  public let rawMessage: RealtimeMessage
}

public struct DeleteAction: PostgresAction, HasOldRecord, HasRawMessage {
  public static let eventType: PostgresChangeEvent = .delete

  public let columns: [Column]
  public let commitTimestamp: Date
  public let oldRecord: [String: AnyJSON]
  public let rawMessage: RealtimeMessage
}

public struct SelectAction: PostgresAction, HasRecord, HasRawMessage {
  public static let eventType: PostgresChangeEvent = .select

  public let columns: [Column]
  public let commitTimestamp: Date
  public let record: [String: AnyJSON]
  public let rawMessage: RealtimeMessage
}

public enum AnyAction: PostgresAction, HasRawMessage {
  public static let eventType: PostgresChangeEvent = .all

  case insert(InsertAction)
  case update(UpdateAction)
  case delete(DeleteAction)
  case select(SelectAction)

  var wrappedAction: any PostgresAction & HasRawMessage {
    switch self {
    case let .insert(action): action
    case let .update(action): action
    case let .delete(action): action
    case let .select(action): action
    }
  }

  public var rawMessage: RealtimeMessage {
    wrappedAction.rawMessage
  }
}

extension HasRecord {
  public func decodeRecord<T: Decodable>(as _: T.Type = T.self, decoder: JSONDecoder) throws -> T {
    try record.decode(as: T.self, decoder: decoder)
  }
}

extension HasOldRecord {
  public func decodeOldRecord<T: Decodable>(
    as _: T.Type = T.self,
    decoder: JSONDecoder
  ) throws -> T {
    try oldRecord.decode(as: T.self, decoder: decoder)
  }
}
