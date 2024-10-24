//
//  RealtimeError.swift
//
//
//  Created by Guilherme Souza on 30/10/23.
//

import Foundation

struct RealtimeError: LocalizedError {
  var errorDescription: String?

  init(_ errorDescription: String) {
    self.errorDescription = errorDescription
  }
}
