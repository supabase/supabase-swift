//
//  DateFormatter.swift
//
//
//  Created by Guilherme Souza on 28/12/23.
//

import ConcurrencyExtras
import Foundation

extension ISO8601DateFormatter {
  package static let iso8601: UncheckedSendable<ISO8601DateFormatter> = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return UncheckedSendable(formatter)
  }()

  package static let iso8601WithFractionalSeconds: UncheckedSendable<ISO8601DateFormatter> = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return UncheckedSendable(formatter)
  }()
}
