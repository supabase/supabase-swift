//
//  RealtimeError.swift
//
//
//  Created by Guilherme Souza on 30/10/23.
//

import Foundation

package struct RealtimeError: LocalizedError {
  package var errorDescription: String?

  package init(_ errorDescription: String) {
    self.errorDescription = errorDescription
  }
}

extension RealtimeError {
  /// The maximum retry attempts reached.
  static var maxRetryAttemptsReached: Self {
    Self("Maximum retry attempts reached.")
  }

  /// The server closed the channel while a subscribe was in flight.
  static var channelClosedByServer: Self {
    Self("Channel was closed by the server while subscribing.")
  }
}
