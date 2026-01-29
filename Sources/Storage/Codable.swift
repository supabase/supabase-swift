//
//  Codable.swift
//
//
//  Created by Guilherme Souza on 18/10/23.
//

import ConcurrencyExtras
import Foundation

/// Test hook for configuring encoder output formatting. Only available in DEBUG builds.
#if DEBUG
  nonisolated(unsafe) public var _unconfiguredEncoderOutputFormatting:
    JSONEncoder.OutputFormatting =
      []
#endif

extension JSONEncoder {
  /// Returns a `JSONEncoder` with default configuration.
  public static func unconfiguredEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    #if DEBUG
      encoder.outputFormatting = _unconfiguredEncoderOutputFormatting
    #endif
    return encoder
  }

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
