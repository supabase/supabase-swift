//
//  Codable.swift
//  Supabase
//
//  Created by Guilherme Souza on 20/01/25.
//

import ConcurrencyExtras
import Foundation

extension JSONDecoder {
  private static let supportedDateFormatters: [UncheckedSendable<ISO8601DateFormatter>] = [
    ISO8601DateFormatter.iso8601WithFractionalSeconds,
    ISO8601DateFormatter.iso8601,
  ]

  /// Default `JSONDecoder` for decoding types from Supabase.
  package static let `default`: JSONDecoder = {
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
}
