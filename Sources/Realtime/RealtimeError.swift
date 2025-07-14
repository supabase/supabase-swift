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

extension RealtimeError {
  /// The maximum retry attempts reached.
  static var maxRetryAttemptsReached: Self {
    Self("Maximum retry attempts reached.")
  }
}
