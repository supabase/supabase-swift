//
//  PostgresValueTypes.swift
//  PostgREST
//
//  Created by Guilherme Souza on 10/10/26.
//

public import Foundation
public import Helpers

// The Swift types `supabase-typegen` emits for Postgres types with no plain Swift counterpart.
// Each exists because it changes what compiles or how a value is encoded: a range column gets the
// range filters and nothing else, an interval or a time column gets no `like`, a `bytea` operand
// is the `\x…` hex form. Each reads and writes the text form PostgREST uses for the column.

/// A Postgres range column, such as `int4range` or `tstzrange`, as its literal: `[1,10)`, `empty`.
///
/// `Bound` is the Swift type of the range's bounds. It is never stored; it keeps a `daterange`
/// operand off an `int4range` column. The literal is not parsed, because Postgres canonicalizes
/// it — `[2024-01-01,2024-01-31]` comes back as `[2024-01-01,2024-02-01)`.
public struct _PostgresRange<Bound>: RawRepresentable, Hashable, Sendable, Codable,
  ExpressibleByStringLiteral, PostgrestFilterValue
{
  /// The range literal, for example `[1,10)`.
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  public init(from decoder: any Decoder) throws {
    self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// A Postgres `interval`, as the text PostgREST sends, for example `1 day 02:00:00`.
///
/// The text is not parsed: its format depends on the server's `IntervalStyle`. Any form Postgres
/// accepts works as an operand or a write, including ISO 8601 (`P1DT2H`).
public struct _PostgresInterval: RawRepresentable, Hashable, Sendable, Codable,
  ExpressibleByStringLiteral, PostgrestFilterValue
{
  /// The interval text, for example `1 day 02:00:00`.
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  public init(from decoder: any Decoder) throws {
    self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// A Postgres `time` or `timetz`, as the text PostgREST sends, for example `13:45:00` or
/// `13:45:00+02`.
public struct _PostgresTime: RawRepresentable, Hashable, Sendable, Codable,
  ExpressibleByStringLiteral, PostgrestFilterValue
{
  /// The time text, for example `13:45:00`.
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  public init(from decoder: any Decoder) throws {
    self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// A Postgres `bytea`, read and written in the `\x…` hex form PostgREST uses, not base64.
public struct _PostgresBytes: Hashable, Sendable, Codable, PostgrestFilterValue {
  /// The bytes.
  public var data: Data

  public init(_ data: Data) {
    self.data = data
  }

  /// The hex form, for example `\xdeadbeef`.
  public var rawValue: String {
    "\\x" + data.map { String(format: "%02x", $0) }.joined()
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    guard let data = Self.data(fromHex: text) else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Expected a bytea in hex form (\\x…), got \(text)")
    }
    self.data = data
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  static func data(fromHex text: String) -> Data? {
    guard text.hasPrefix("\\x") else { return nil }
    let digits = Array(text.utf8.dropFirst(2))
    guard digits.count.isMultiple(of: 2) else { return nil }
    var data = Data(capacity: digits.count / 2)
    for index in stride(from: 0, to: digits.count, by: 2) {
      guard let byte = UInt8(String(decoding: digits[index...index + 1], as: UTF8.self), radix: 16)
      else { return nil }
      data.append(byte)
    }
    return data
  }
}

/// A column whose Postgres type has no Swift mapping: a composite, a geometric type, an extension
/// type. It holds whatever JSON PostgREST sends — an object for a composite, a string for most
/// other types — and writes it back unchanged.
///
/// It has no filters: Postgres has no equality for a composite (`0A000`) or a `point` (`42883`).
/// Use ``_PostgrestFilterableExpression/raw(_:)`` for an operator the type supports.
public struct _PostgresUnmapped: Hashable, Sendable, Codable {
  /// The value as PostgREST sends it.
  public var value: JSONValue

  public init(_ value: JSONValue) {
    self.value = value
  }

  public init(from decoder: any Decoder) throws {
    self.value = try JSONValue(from: decoder)
  }

  public func encode(to encoder: any Encoder) throws {
    try value.encode(to: encoder)
  }
}
