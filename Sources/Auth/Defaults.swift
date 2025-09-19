//
//  Defaults.swift
//
//
//  Created by Guilherme Souza on 14/12/23.
//

import ConcurrencyExtras
import Foundation

extension AuthClient.Configuration {
  /// The default headers used by the ``AuthClient``.
  public static let defaultHeaders: [String: String] = [
    "X-Client-Info": "auth-swift/\(version)"
  ]

  /// The default ``AuthFlowType`` used when initializing a ``AuthClient`` instance.
  public static let defaultFlowType: AuthFlowType = .pkce

  /// The default value when initializing a ``AuthClient`` instance.
  public static let defaultAutoRefreshToken: Bool = true
}

extension JSONEncoder {
  /// The JSONEncoder instance used for encoding Auth requests.
  static let auth: JSONEncoder = {
    let encoder = JSONEncoder.supabase()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return encoder
  }()
}

extension JSONDecoder {
  /// The JSONDecoder instance used for decoding Auth responses.
  static let auth: JSONDecoder = {
    let decoder = JSONDecoder.supabase()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }()
}