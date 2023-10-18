//
//  File.swift
//
//
//  Created by Guilherme Souza on 18/10/23.
//

import Foundation

extension JSONEncoder {
  public static let defaultStorageEncoder: JSONEncoder = {
    JSONEncoder()
  }()
}

extension JSONDecoder {
  public static let defaultStorageDecoder: JSONDecoder = {
    JSONDecoder()
  }()
}
