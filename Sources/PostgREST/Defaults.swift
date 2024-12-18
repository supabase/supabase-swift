//
//  Defaults.swift
//
//
//  Created by Guilherme Souza on 14/12/23.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers

let version = Helpers.version

extension PostgrestClient.Configuration {
  private static let supportedDateFormatters: [UncheckedSendable<ISO8601DateFormatter>] = [
    ISO8601DateFormatter.iso8601WithFractionalSeconds,
    ISO8601DateFormatter.iso8601,
  ]

  /// The default `JSONDecoder` instance for ``PostgrestClient`` responses.
  public static let jsonDecoder = { () -> JSONDecoder in
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let string = try container.decode(String.self)

      for formatter in supportedDateFormatters {
        if let date = formatter.value.date(from: string) {
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

  public static let defaultHeaders: HTTPFields = [
    .xClientInfo: "postgrest-swift/\(version)"
  ]
}
