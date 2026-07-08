//
//  JSONCoding.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 08/07/26.
//
import Foundation

/// Shared JSON coders used by generated code. Dates are ISO-8601 with
/// fractional seconds, matching the mock server and the spec timestamps.
public enum JSONCoding {
  public static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .custom { date, enc in
      var container = enc.singleValueContainer()
      try container.encode(iso8601.string(from: date))
    }
    return encoder
  }()

  public static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { dec in
      let container = try dec.singleValueContainer()
      let string = try container.decode(String.self)
      guard let date = iso8601.date(from: string) ?? iso8601NoFraction.date(from: string) else {
        throw DecodingError.dataCorruptedError(
          in: container,
          debugDescription: "Invalid ISO-8601 date: \(string)"
        )
      }
      return date
    }
    return decoder
  }()

  /// ISO-8601 string with fractional seconds, for `@httpQuery` timestamp params.
  public static func iso8601String(_ date: Date) -> String {
    iso8601.string(from: date)
  }

  nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  nonisolated(unsafe) private static let iso8601NoFraction: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()
}
