//
//  Codable.swift
//  Supabase
//
//  Created by Guilherme Souza on 20/01/25.
//

import ConcurrencyExtras
package import Foundation
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

/// Tries each of `attempts` in order, returning the first one that succeeds.
///
/// Useful for discriminated-union-style `Decodable` types backed by
/// different, mutually exclusive JSON shapes. A naive `try?`-based fallback
/// silently discards earlier failures, so a genuine decoding error in the
/// first shape (e.g. a malformed field) gets replaced by the (less useful)
/// error from the last shape tried. This surfaces every attempt's failure
/// instead.
///
/// ```swift
/// public init(from decoder: any Decoder) throws {
///   self = try decodeOneOf(
///     { .details(try Details(from: decoder)) },
///     { .redirect(try Redirect(from: decoder)) }
///   )
/// }
/// ```
package func decodeOneOf<T>(_ attempts: (() throws -> T)...) throws -> T {
  var errors: [any Error] = []
  for attempt in attempts {
    do {
      return try attempt()
    } catch {
      errors.append(error)
    }
  }
  throw AllDecodingAttemptsFailedError(errors: errors)
}

/// Every attempt passed to ``decodeOneOf(_:)`` failed. Carries all of their
/// errors, not just the last one tried.
package struct AllDecodingAttemptsFailedError: Error, CustomStringConvertible {
  package let errors: [any Error]

  package var description: String {
    errors.enumerated()
      .map { "attempt \($0.offset + 1): \($0.element)" }
      .joined(separator: "\n")
  }
}
