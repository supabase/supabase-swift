//
//  Defaults.swift
//
//
//  Created by Guilherme Souza on 14/12/23.
//

import ConcurrencyExtras
package import Foundation
import Helpers

extension PostgrestClient.Configuration {
  /// The decoder of typed Postgres changes on a channel whose client has no database decoder,
  /// such as a standalone `RealtimeClient`.
  package static let jsonDecoder = JSONDecoder.supabase()

  /// The encoder of the typed API: ``encoder`` with its key strategy ignored. The typed API takes
  /// column names from `CodingKeys` and from the keys of the encoded body, and a key strategy
  /// would rename them. Every other setting, such as the date strategy, applies.
  var typedEncoder: JSONEncoder { encoder.ignoringKeyStrategy() }

  /// The decoder of the typed API: ``decoder`` with its key strategy ignored. The `CodingKeys` of
  /// a typed row already hold the column names. Every other setting, such as the date strategy,
  /// applies.
  var typedDecoder: JSONDecoder { decoder.ignoringKeyStrategy() }

  /// Sent unless the configured headers set the same name.
  static let defaultHeaders: HTTPFields = [
    .xClientInfo: clientInfo(library: "postgrest-swift")
  ]
}
