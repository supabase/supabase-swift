//
//  Defaults.swift
//
//
//  Created by Guilherme Souza on 14/12/23.
//

import Foundation
@_spi(Internal) import _Helpers

let version = _Helpers.version

extension PostgrestClient.Configuration {
  private static let supportedDateFormatters: [ISO8601DateFormatter] = [
    { () -> ISO8601DateFormatter in
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      return formatter
    }(),
    { () -> ISO8601DateFormatter in
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime]
      return formatter
    }(),
  ]

  /// The default `JSONDecoder` instance for ``PostgrestClient`` responses.
  public static let jsonDecoder = { () -> JSONDecoder in
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let string = try container.decode(String.self)

      for formatter in supportedDateFormatters {
        if let date = formatter.date(from: string) {
          return date
        }
      }

      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Invalid date format: \(string)"
      )
    }
    return decoder
  }()

  /// The default `JSONEncoder` instance for ``PostgrestClient`` requests.
  public static let jsonEncoder = { () -> JSONEncoder in
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()

  public static let defaultHeaders: [String: String] = [
    "X-Client-Info": "postgrest-swift/\(version)",
  ]
}
