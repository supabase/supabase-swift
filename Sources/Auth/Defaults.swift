//
//  Defaults.swift
//
//
//  Created by Guilherme Souza on 14/12/23.
//

@_spi(Internal) import _Helpers
import Foundation

extension AuthClient.Configuration {
  private static let dateFormatterWithFractionalSeconds = { () -> ISO8601DateFormatter in
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static let dateFormatter = { () -> ISO8601DateFormatter in
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  /// The default JSONEncoder instance used by the ``AuthClient``.
  public static let jsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      let string = dateFormatter.string(from: date)
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

      let supportedFormatters = [dateFormatterWithFractionalSeconds, dateFormatter]

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
}
