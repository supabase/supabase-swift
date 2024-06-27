//
//  Defaults.swift
//
//
//  Created by Guilherme Souza on 14/12/23.
//

import Foundation
import Helpers

extension AuthClient.Configuration {
  /// The default JSONEncoder instance used by the ``AuthClient``.
  public static let jsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      let string = DateFormatter.iso8601.string(from: date)
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

      let supportedFormatters: [DateFormatter] = [.iso8601, .iso8601_noMilliseconds]

      for formatter in supportedFormatters {
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

  public static let defaultHeaders: [String: String] = [
    "X-Client-Info": "auth-swift/\(version)",
  ]

  /// The default ``AuthFlowType`` used when initializing a ``AuthClient`` instance.
  public static let defaultFlowType: AuthFlowType = .pkce

  /// The default value when initializing a ``AuthClient`` instance.
  public static let defaultAutoRefreshToken: Bool = true

  static let defaultStorageKey = "supabase.auth.token"
}
