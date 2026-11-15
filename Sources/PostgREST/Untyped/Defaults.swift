//
//  Defaults.swift
//
//
//  Created by Guilherme Souza on 14/12/23.
//

import ConcurrencyExtras
package import Foundation

extension PostgrestClient.Configuration {
  /// The fixed decoder of the typed API. Not public, so no caller can change the settings the
  /// column names depend on. Typed Postgres changes decode with it too.
  package static let jsonDecoder = JSONDecoder.supabase()

  /// The fixed encoder of the typed API. Not public, so no caller can change the settings the
  /// column names depend on.
  package static let jsonEncoder = JSONEncoder.supabase()

  /// Sent unless the configured headers set the same name.
  static let defaultHeaders: HTTPFields = [
    .xClientInfo: clientInfo(library: "postgrest-swift")
  ]
}
