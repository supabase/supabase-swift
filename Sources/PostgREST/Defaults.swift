//
//  Defaults.swift
//
//
//  Created by Guilherme Souza on 14/12/23.
//

import ConcurrencyExtras
import Foundation
import Helpers

let version = Helpers.version

extension PostgrestClient.Configuration {
  /// The default `JSONDecoder` instance for ``PostgrestClient`` responses.
  public static let jsonDecoder: JSONDecoder = {
    JSONDecoder.supabase()
  }()

  /// The default `JSONEncoder` instance for ``PostgrestClient`` requests.
  public static let jsonEncoder: JSONEncoder = {
    JSONEncoder.supabase()
  }()

  /// The default headers for ``PostgrestClient`` requests.
  public static let defaultHeaders: [String: String] = [
    "X-Client-Info": "postgrest-swift/\(version)"
  ]
}
