//
//  DateFormatter.swift
//
//
//  Created by Guilherme Souza on 28/12/23.
//

import Foundation

extension Date.ISO8601FormatStyle {
  fileprivate func currentTimestamp(includingFractionalSeconds: Bool) -> Self {
    year().month().day()
      .dateTimeSeparator(.standard)
      .time(includingFractionalSeconds: includingFractionalSeconds)
  }
}

extension Date {
  package var iso8601String: String {
    formatted(.iso8601.currentTimestamp(includingFractionalSeconds: true))
  }
}

extension String {
  package var date: Date? {
    if let date = try? Date(
      self,
      strategy: .iso8601.currentTimestamp(includingFractionalSeconds: true)
    ) {
      return date
    }
    return try? Date(
      self,
      strategy: .iso8601.currentTimestamp(includingFractionalSeconds: false)
    )
  }
}
