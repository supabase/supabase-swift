//
//  Defaults.swift
//
//
//  Created by Guilherme Souza on 14/12/23.
//

import ConcurrencyExtras
package import Foundation

let version = Helpers.version

extension PostgrestClient.Configuration {
  /// The fixed decoder of the typed API. Not public, so no caller can change the settings the
  /// column names depend on. Typed Postgres changes decode with it too.
  package static let jsonDecoder = JSONDecoder.supabase()

  /// The fixed encoder of the typed API. Not public, so no caller can change the settings the
  /// column names depend on.
  package static let jsonEncoder = JSONEncoder.supabase()

  /// The default HTTP headers added to every request from a ``PostgrestClient``.
  ///
  /// Includes an `X-Client-Info` header that identifies the SDK name and version.
  public static let defaultHeaders: [String: String] = [
    "X-Client-Info": "postgrest-swift/\(version)"
  ]
}
