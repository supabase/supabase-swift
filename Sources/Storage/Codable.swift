//
//  Codable.swift
//
//
//  Created by Guilherme Souza on 18/10/23.
//

import ConcurrencyExtras
import Foundation

extension JSONEncoder {
  static let unconfiguredEncoder: JSONEncoder = .init()

  /// Default `JSONEncoder` for encoding types to Supabase Storage.
  public static func storage() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return encoder
  }
}

extension JSONDecoder {
  /// Default `JSONDecoder` for decoding types from Supabase Storage.
  public static func storage() -> JSONDecoder {
    JSONDecoder.supabase()
  }
}
