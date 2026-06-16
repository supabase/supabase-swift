//
//  Codable.swift
//  Supabase
//
//  Created by Guilherme Souza on 20/01/25.
//

import ConcurrencyExtras
import Foundation
import XCTestDynamicOverlay

extension JSONDecoder {
  /// Default `JSONDecoder` for decoding types from Supabase.
  package static func supabase() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let string = try container.decode(String.self)

      if let date = string.date {
        return date
      }

      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid date format: \(string)"
      )
    }
    return decoder
  }
}
extension JSONEncoder {
  /// Default `JSONEncoder` for encoding types to Supabase.
  package static func supabase() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      let string = date.iso8601String
      try container.encode(string)
    }

    #if DEBUG
      if isTesting {
        encoder.outputFormatting = [.sortedKeys]
      }
    #endif

    return encoder
  }
}
