//
//  Codable.swift
//
//
//  Created by Guilherme Souza on 18/10/23.
//

import Foundation

extension JSONEncoder {
  public static let defaultStorageEncoder: JSONEncoder = .init()
}

extension JSONDecoder {
  public static let defaultStorageDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let string = try container.decode(String.self)

      if let date = formatter.date(from: string) {
        return date
      }

      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Invalid date format: \(string)"
      )
    }

    return decoder
  }()
}
