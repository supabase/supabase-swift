//
//  JSONValue+Codable.swift
//
//
//  Created by Guilherme Souza on 20/01/24.
//

public import Foundation

extension JSONValue {
  /// The decoder for the SDK's own `JSONValue` round trips. Never handed to a caller's coder
  /// parameter, so no one can change its settings.
  package static let decoder: JSONDecoder = JSONDecoder.supabase()

  /// The encoder for the SDK's own `JSONValue` round trips. Never handed to a caller's coder
  /// parameter, so no one can change its settings.
  package static let encoder: JSONEncoder = JSONEncoder.supabase()
}

extension JSONValue {
  /// Initialize an ``JSONValue`` from an `Encodable` value.
  /// - Parameter encoder: The `JSONEncoder` used to serialize `value`. `nil` uses
  ///   `JSONEncoder.supabase()`.
  public init(_ value: some Encodable, encoder: JSONEncoder? = nil) throws {
    if let value = value as? JSONValue {
      self = value
    } else if let string = value as? String {
      self = .string(string)
    } else if let bool = value as? Bool {
      self = .bool(bool)
    } else if let int = value as? Int {
      self = .integer(int)
    } else if let double = value as? Double {
      self = .double(double)
    } else {
      let data = try (encoder ?? JSONValue.encoder).encode(value)
      self = try JSONValue.decoder.decode(JSONValue.self, from: data)
    }
  }

  /// Decodes self instance as `Decodable` type.
  /// - Parameter decoder: The `JSONDecoder` used to decode the value. `nil` uses
  ///   `JSONDecoder.supabase()`.
  public func decode<T: Decodable>(
    as type: T.Type = T.self,
    decoder: JSONDecoder? = nil
  ) throws -> T {
    let data = try JSONValue.encoder.encode(self)
    return try (decoder ?? JSONValue.decoder).decode(type, from: data)
  }
}

extension JSONArray {
  /// Decodes self instance as array of `Decodable` type.
  /// - Parameter decoder: The `JSONDecoder` used to decode the elements. `nil` uses
  ///   `JSONDecoder.supabase()`.
  public func decode<T: Decodable>(
    as _: T.Type = T.self,
    decoder: JSONDecoder? = nil
  ) throws -> [T] {
    try JSONValue.array(self).decode(as: [T].self, decoder: decoder)
  }
}

extension JSONObject {
  /// Decodes self instance as `Decodable` type.
  /// - Parameter decoder: The `JSONDecoder` used to decode the object. `nil` uses
  ///   `JSONDecoder.supabase()`.
  public func decode<T: Decodable>(
    as _: T.Type = T.self,
    decoder: JSONDecoder? = nil
  ) throws -> T {
    try JSONValue.object(self).decode(as: T.self, decoder: decoder)
  }

  /// Initialize JSONObject from an `Encodable` type
  /// - Parameter encoder: The `JSONEncoder` used to serialize `value`. `nil` uses
  ///   `JSONEncoder.supabase()`.
  public init(_ value: some Encodable, encoder: JSONEncoder? = nil) throws {
    guard let object = try JSONValue(value, encoder: encoder).objectValue else {
      throw DecodingError.typeMismatch(
        JSONObject.self,
        DecodingError.Context(
          codingPath: [],
          debugDescription: "Expected to decode value to \(JSONObject.self)."
        )
      )
    }

    self = object
  }
}
