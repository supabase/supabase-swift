//
//  JSONValue.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/26.
//

import Foundation

/// Codable JSON value without external dependencies.
public enum JSONValue: Codable, Sendable, Equatable {
  case string(String)
  case double(Double)
  case int(Int)
  case bool(Bool)
  case null
  indirect case array([JSONValue])
  indirect case object([String: JSONValue])

  public init(from decoder: any Decoder) throws {
    let c = try decoder.singleValueContainer()
    if let v = try? c.decode(Bool.self)             { self = .bool(v);   return }
    if let v = try? c.decode(Int.self)              { self = .int(v);    return }
    if let v = try? c.decode(Double.self)           { self = .double(v); return }
    if let v = try? c.decode(String.self)           { self = .string(v); return }
    if c.decodeNil()                                { self = .null;      return }
    if let v = try? c.decode([JSONValue].self)      { self = .array(v);  return }
    if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
    throw DecodingError.dataCorrupted(
      .init(codingPath: decoder.codingPath, debugDescription: "Cannot decode JSONValue")
    )
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .string(let v): try c.encode(v)
    case .double(let v): try c.encode(v)
    case .int(let v):    try c.encode(v)
    case .bool(let v):   try c.encode(v)
    case .null:          try c.encodeNil()
    case .array(let v):  try c.encode(v)
    case .object(let v): try c.encode(v)
    }
  }
}

extension JSONValue: ExpressibleByStringLiteral {
  public init(stringLiteral v: String) { self = .string(v) }
}
extension JSONValue: ExpressibleByIntegerLiteral {
  public init(integerLiteral v: Int) { self = .int(v) }
}
extension JSONValue: ExpressibleByFloatLiteral {
  public init(floatLiteral v: Double) { self = .double(v) }
}
extension JSONValue: ExpressibleByBooleanLiteral {
  public init(booleanLiteral v: Bool) { self = .bool(v) }
}
extension JSONValue: ExpressibleByNilLiteral {
  public init(nilLiteral: ()) { self = .null }
}
extension JSONValue: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}
extension JSONValue: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (String, JSONValue)...) {
    self = .object(Dictionary(uniqueKeysWithValues: elements))
  }
}
