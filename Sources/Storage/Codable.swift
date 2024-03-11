//
//  Codable.swift
//
//
//  Created by Guilherme Souza on 18/10/23.
//

import ConcurrencyExtras
import Foundation

extension JSONEncoder {
  public static let defaultStorageEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return encoder
  }()
}

extension JSONDecoder {
  public static let defaultStorageDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    let formatter = LockIsolated(ISO8601DateFormatter())
    formatter.withValue {
      $0.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let string = try container.decode(String.self)

      if let date = formatter.withValue({ $0.date(from: string) }) {
        return date
      }

      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Invalid date format: \(string)"
      )
    }

    return decoder
  }()
}
