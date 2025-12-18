//
//  Codable.swift
//
//
//  Created by Guilherme Souza on 18/10/23.
//

import ConcurrencyExtras
import Foundation

extension JSONEncoder {
  static func unconfigured() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }
}

extension JSONDecoder {
  static func unconfigured() -> JSONDecoder { .init() }
}
