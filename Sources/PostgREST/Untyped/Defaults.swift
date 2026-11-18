//
//  Defaults.swift
//
//
//  Created by Guilherme Souza on 14/12/23.
//

import ConcurrencyExtras
package import Foundation

extension PostgrestClient.Configuration {
  /// The default decoder of typed Postgres changes. Not public, so no caller can change the
  /// settings the column names depend on.
  package static let jsonDecoder = JSONDecoder.supabase()

  /// The encoder of the typed API: ``encoder`` with its key strategy forced to
  /// `.useDefaultKeys`.
  ///
  /// The typed API takes column names from `CodingKeys` and from the keys of the encoded body.
  /// A key strategy would rename those keys, so the body and the `columns` query item would
  /// name columns that do not exist. Every other setting, such as the date strategy, applies.
  var typedEncoder: JSONEncoder {
    guard case .useDefaultKeys = encoder.keyEncodingStrategy else {
      let copy = JSONEncoder()
      copy.outputFormatting = encoder.outputFormatting
      copy.dateEncodingStrategy = encoder.dateEncodingStrategy
      copy.dataEncodingStrategy = encoder.dataEncodingStrategy
      copy.nonConformingFloatEncodingStrategy = encoder.nonConformingFloatEncodingStrategy
      copy.userInfo = encoder.userInfo
      return copy
    }
    return encoder
  }

  /// The decoder of the typed API: ``decoder`` with its key strategy forced to
  /// `.useDefaultKeys`.
  ///
  /// The `CodingKeys` of a typed row already hold the column names. A key strategy would rename
  /// the response keys first, so they would no longer match. Every other setting, such as the
  /// date strategy, applies.
  var typedDecoder: JSONDecoder {
    guard case .useDefaultKeys = decoder.keyDecodingStrategy else {
      let copy = JSONDecoder()
      copy.dateDecodingStrategy = decoder.dateDecodingStrategy
      copy.dataDecodingStrategy = decoder.dataDecodingStrategy
      copy.nonConformingFloatDecodingStrategy = decoder.nonConformingFloatDecodingStrategy
      copy.userInfo = decoder.userInfo
      copy.allowsJSON5 = decoder.allowsJSON5
      copy.assumesTopLevelDictionary = decoder.assumesTopLevelDictionary
      return copy
    }
    return decoder
  }

  /// Sent unless the configured headers set the same name.
  static let defaultHeaders: HTTPFields = [
    .xClientInfo: clientInfo(library: "postgrest-swift")
  ]
}
