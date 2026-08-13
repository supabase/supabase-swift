//
//  Codable.swift
//
//
//  Created by Guilherme Souza on 18/10/23.
//

import ConcurrencyExtras
import Foundation

extension JSONEncoder {
  /// Default encoder used by ``StorageClientConfiguration`` when no `encoder` is supplied,
  /// converting Swift's `camelCase` property names to the API's `snake_case` keys.
  static let storageEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return encoder
  }()

  static let unconfiguredEncoder: JSONEncoder = .init()
}
