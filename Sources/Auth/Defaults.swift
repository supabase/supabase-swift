//
//  Defaults.swift
//
//
//  Created by Guilherme Souza on 14/12/23.
//

import ConcurrencyExtras
import Foundation
import Helpers

extension AuthClient.Configuration {
  private static let supportedDateFormatters: [UncheckedSendable<ISO8601DateFormatter>] = [
    ISO8601DateFormatter.iso8601WithFractionalSeconds,
    ISO8601DateFormatter.iso8601,
  ]

  /// The default JSONEncoder instance used by the ``AuthClient``.
  public static let jsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.dateEncodingStrategy = .custom { date, encoder in
      let string = ISO8601DateFormatter.iso8601WithFractionalSeconds.value.string(from: date)
      var container = encoder.singleValueContainer()
      try container.encode(string)
    }
    return encoder
  }()

  /// The default JSONDecoder instance used by the ``AuthClient``.
  public static let jsonDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
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

  public static let defaultHeaders: [String: String] = [
    "X-Client-Info": "auth-swift/\(version)",
  ]

  /// The default ``AuthFlowType`` used when initializing a ``AuthClient`` instance.
  public static let defaultFlowType: AuthFlowType = .pkce

  /// The default value when initializing a ``AuthClient`` instance.
  public static let defaultAutoRefreshToken: Bool = true

  static let defaultStorageKey = "supabase.auth.token"
}
