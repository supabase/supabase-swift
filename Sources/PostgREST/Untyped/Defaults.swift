//
//  Defaults.swift
//
//
//  Created by Guilherme Souza on 14/12/23.
//

import ConcurrencyExtras
public import Foundation

let version = Helpers.version

extension PostgrestClient.Configuration {
  /// The default `JSONDecoder` used for decoding PostgREST responses.
  ///
  /// Pre-configured with Supabase-compatible date decoding and key strategies.
  /// Use this as a starting point if you need a custom decoder.
  public static let jsonDecoder: JSONDecoder = {
    JSONDecoder.supabase()
  }()

  /// The default `JSONEncoder` used for encoding PostgREST request bodies.
  ///
  /// Pre-configured with Supabase-compatible date encoding and key strategies.
  /// Use this as a starting point if you need a custom encoder.
  public static let jsonEncoder: JSONEncoder = {
    JSONEncoder.supabase()
  }()

  /// The default HTTP headers added to every request from a ``PostgrestClient``.
  ///
  /// Includes an `X-Client-Info` header that identifies the SDK name and version.
  public static let defaultHeaders: [String: String] = [
    "X-Client-Info": "postgrest-swift/\(version)"
  ]
}
