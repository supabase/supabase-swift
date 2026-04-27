//
//  PostgresChange.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/25.
//

import Foundation

public enum PostgresChange<T: Sendable>: Sendable {
  case insert(T)
  case update(old: T, new: T)
  case delete(old: T)

  static func decode(from payload: [String: JSONValue]) throws -> PostgresChange<T>
  where T: Decodable {
    guard case .object(let data) = payload["data"] else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: [], debugDescription: "Missing 'data'")
      )
    }
    guard case .string(let type) = data["type"] else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: [], debugDescription: "Missing 'type'")
      )
    }

    func decodeRecord(_ key: String) throws -> T {
      guard case .object(let obj) = data[key] else {
        throw DecodingError.keyNotFound(
          _AnyKey(stringValue: key),
          .init(codingPath: [], debugDescription: "Missing '\(key)'")
        )
      }
      let recordData = try JSONEncoder().encode(obj)
      return try JSONDecoder().decode(T.self, from: recordData)
    }

    switch type {
    case "INSERT":
      return .insert(try decodeRecord("record"))
    case "UPDATE":
      return .update(old: try decodeRecord("old_record"), new: try decodeRecord("record"))
    case "DELETE":
      return .delete(old: try decodeRecord("old_record"))
    default:
      throw DecodingError.dataCorrupted(
        .init(codingPath: [], debugDescription: "Unknown type: \(type)")
      )
    }
  }
}

// Helper to satisfy DecodingError.keyNotFound CodingKey requirement.
private struct _AnyKey: CodingKey {
  var stringValue: String
  var intValue: Int? { nil }
  init(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}
