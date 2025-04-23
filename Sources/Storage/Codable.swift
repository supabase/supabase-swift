//
//  Codable.swift
//
//
//  Created by Guilherme Souza on 18/10/23.
//

import ConcurrencyExtras
import Foundation

extension JSONEncoder {
  @available(*, deprecated, message: "Access to storage encoder is going to be removed.")
  public static let defaultStorageEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return encoder
  }()

  static let unconfiguredEncoder: JSONEncoder = .init()
}

extension JSONDecoder {
  @available(*, deprecated, message: "Access to storage decoder is going to be removed.")
  public static let defaultStorageDecoder: JSONDecoder = {
    JSONDecoder.supabase()
  }()
}
