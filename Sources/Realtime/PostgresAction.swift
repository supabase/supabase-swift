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

public protocol PostgresAction: Equatable, Sendable {
  static var eventType: PostgresChangeEvent { get }
}

public protocol HasRecord {
  var record: JSONObject { get }
}

public protocol HasOldRecord {
  var oldRecord: JSONObject { get }
}

protocol HasRawMessage {
  var rawMessage: _RealtimeMessage { get }
}

public struct InsertAction: PostgresAction, HasRecord, HasRawMessage {
  public static let eventType: PostgresChangeEvent = .insert

  public let columns: [Column]
  public let commitTimestamp: Date
  public let record: [String: AnyJSON]
  var rawMessage: _RealtimeMessage
}

public struct UpdateAction: PostgresAction, HasRecord, HasOldRecord, HasRawMessage {
  public static let eventType: PostgresChangeEvent = .update

  public let columns: [Column]
  public let commitTimestamp: Date
  public let record, oldRecord: [String: AnyJSON]
  var rawMessage: _RealtimeMessage
}

public struct DeleteAction: PostgresAction, HasOldRecord, HasRawMessage {
  public static let eventType: PostgresChangeEvent = .delete

  public let columns: [Column]
  public let commitTimestamp: Date
  public let oldRecord: [String: AnyJSON]
  var rawMessage: _RealtimeMessage
}

public struct SelectAction: PostgresAction, HasRecord, HasRawMessage {
  public static let eventType: PostgresChangeEvent = .select

  public let columns: [Column]
  public let commitTimestamp: Date
  public let record: [String: AnyJSON]
  var rawMessage: _RealtimeMessage
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

  var rawMessage: _RealtimeMessage {
    wrappedAction.rawMessage
  }
}

extension HasRecord {
  public func decodeRecord<T: Decodable>() throws -> T {
    try record.decode(T.self)
  }
}

extension HasOldRecord {
  public func decodeOldRecord<T: Decodable>() throws -> T {
    try oldRecord.decode(T.self)
  }
}
