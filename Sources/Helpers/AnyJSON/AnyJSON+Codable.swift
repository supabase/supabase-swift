//
//  AnyJSON+Codable.swift
//
//
//  Created by Guilherme Souza on 20/01/24.
//

import Foundation

extension AnyJSON {
  /// The decoder instance used for transforming AnyJSON to some Codable type.
  public static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dataDecodingStrategy = .base64
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let dateString = try container.decode(String.self)

      let date =
        ISO8601DateFormatter.iso8601WithFractionalSeconds.value.date(from: dateString)
        ?? ISO8601DateFormatter.iso8601.value.date(from: dateString)

      guard let decodedDate = date else {
        throw DecodingError.dataCorruptedError(
          in: container, debugDescription: "Invalid date format: \(dateString)"
        )
      }

      return decodedDate
    }
    return decoder
  }()

  /// The encoder instance used for transforming AnyJSON to some Codable type.
  public static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dataEncodingStrategy = .base64
    encoder.dateEncodingStrategy = .custom { date, encoder in
      let string = ISO8601DateFormatter.iso8601WithFractionalSeconds.value.string(from: date)
      var container = encoder.singleValueContainer()
      try container.encode(string)
    }
    return encoder
  }()
}

extension AnyJSON {
  /// Initialize an ``AnyJSON`` from a ``Codable`` value.
  public init(_ value: some Codable) throws {
    if let value = value as? AnyJSON {
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
      let data = try AnyJSON.encoder.encode(value)
      self = try AnyJSON.decoder.decode(AnyJSON.self, from: data)
    }
  }

  /// Decodes self instance as `Decodable` type.
  public func decode<T: Decodable>(
    as type: T.Type = T.self,
    decoder: JSONDecoder = AnyJSON.decoder
  ) throws -> T {
    let data = try AnyJSON.encoder.encode(self)
    return try decoder.decode(type, from: data)
  }
}

extension JSONArray {
  /// Decodes self instance as array of `Decodable` type.
  public func decode<T: Decodable>(
    as _: T.Type = T.self,
    decoder: JSONDecoder = AnyJSON.decoder
  ) throws -> [T] {
    try AnyJSON.array(self).decode(as: [T].self, decoder: decoder)
  }
}

extension JSONObject {
  /// Decodes self instance as `Decodable` type.
  public func decode<T: Decodable>(
    as _: T.Type = T.self,
    decoder: JSONDecoder = AnyJSON.decoder
  ) throws -> T {
    try AnyJSON.object(self).decode(as: T.self, decoder: decoder)
  }

  /// Initialize JSONObject from a `Codable` type
  public init(_ value: some Codable) throws {
    guard let object = try AnyJSON(value).objectValue else {
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
