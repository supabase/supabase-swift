//
//  Codable.swift
//
//
//  Created by Guilherme Souza on 18/10/23.
//

import Foundation

extension JSONEncoder {
  /// The one encoder Storage uses for request bodies. Wire keys that are not the Swift
  /// property name are spelled in each type's `CodingKeys`.
  static let storage = JSONEncoder.supabase()
}

extension JSONDecoder {
  /// The one decoder Storage uses for response bodies.
  static let storage = JSONDecoder.supabase()
}
