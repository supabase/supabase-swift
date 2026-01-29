//
//  Codable.swift
//
//
//  Created by Guilherme Souza on 18/10/23.
//

import ConcurrencyExtras
import Foundation

extension JSONEncoder {
  /// Returns a `JSONEncoder` with default configuration.
  static func unconfiguredEncoder() -> JSONEncoder {
    JSONEncoder.supabase()
  }

  /// Default `JSONEncoder` for encoding types to Supabase Storage.
  public static func storage() -> JSONEncoder {
    let encoder = JSONEncoder.supabase()
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
