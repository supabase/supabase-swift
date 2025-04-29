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
  /// The default JSONEncoder instance used by the ``AuthClient``.
  public static let jsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder.supabase()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return encoder
  }()

  /// The default JSONDecoder instance used by the ``AuthClient``.
  public static let jsonDecoder: JSONDecoder = {
    let decoder = JSONDecoder.supabase()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }()

  /// The default headers used by the ``AuthClient``.
  public static let defaultHeaders: [String: String] = [
    "X-Client-Info": "auth-swift/\(version)"
  ]

  /// The default ``AuthFlowType`` used when initializing a ``AuthClient`` instance.
  public static let defaultFlowType: AuthFlowType = .pkce

  /// The default value when initializing a ``AuthClient`` instance.
  public static let defaultAutoRefreshToken: Bool = true
}
