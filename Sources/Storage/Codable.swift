//
//  Codable.swift
//
//
//  Created by Guilherme Souza on 18/10/23.
//

import ConcurrencyExtras
import Foundation

extension JSONEncoder {
  static let defaultStorageEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return encoder
  }()

  static let unconfiguredEncoder: JSONEncoder = .init()
}

extension JSONDecoder {
  static let defaultStorageDecoder: JSONDecoder = {
    JSONDecoder.supabase()
  }()
}
