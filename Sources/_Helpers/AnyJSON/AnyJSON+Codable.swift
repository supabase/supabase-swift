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

      let date = DateFormatter.iso8601.date(from: dateString) ?? DateFormatter
        .iso8601_noMilliseconds.date(from: dateString)

      guard let decodedDate = date else {
        throw DecodingError.typeMismatch(
          Date.self,
          DecodingError.Context(
            codingPath: container.codingPath,
            debugDescription: "String is not a valid Date"
          )
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
    encoder.dateEncodingStrategy = .formatted(DateFormatter.iso8601)
    return encoder
  }()
}

extension AnyJSON {
  /// Initialize an ``AnyJSON`` from a ``Codable`` value.
  public init(_ value: some Codable) throws {
    if let value = value as? AnyJSON {
      self = value
    } else {
      let data = try AnyJSON.encoder.encode(value)
      self = try AnyJSON.decoder.decode(AnyJSON.self, from: data)
    }
  }

  public func decode<T: Decodable>(
    as _: T.Type = T.self,
    decoder: JSONDecoder = AnyJSON.decoder
  ) throws -> T {
    let data = try AnyJSON.encoder.encode(self)
    return try decoder.decode(T.self, from: data)
  }
}

extension JSONArray {
  public func decode<T: Decodable>(
    as _: T.Type = T.self,
    decoder: JSONDecoder = AnyJSON.decoder
  ) throws -> [T] {
    try AnyJSON.array(self).decode(as: [T].self, decoder: decoder)
  }
}

extension JSONObject {
  public func decode<T: Decodable>(
    as _: T.Type = T.self,
    decoder: JSONDecoder = AnyJSON.decoder
  ) throws -> T {
    try AnyJSON.object(self).decode(as: T.self, decoder: decoder)
  }

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
