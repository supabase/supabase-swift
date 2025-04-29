//
//  DateFormatter.swift
//
//
//  Created by Guilherme Souza on 28/12/23.
//

import Foundation

extension DateFormatter {
  fileprivate static func iso8601(includingFractionalSeconds: Bool) -> DateFormatter {
    includingFractionalSeconds ? iso8601Fractional : iso8601Whole
  }

  fileprivate static let iso8601Fractional: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .iso8601)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
  }()

  fileprivate static let iso8601Whole: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .iso8601)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
  }()
}

@available(iOS 15, macOS 12, tvOS 15, watchOS 8, *)
extension Date.ISO8601FormatStyle {
  fileprivate func currentTimestamp(includingFractionalSeconds: Bool) -> Self {
    year().month().day()
      .dateTimeSeparator(.standard)
      .time(includingFractionalSeconds: includingFractionalSeconds)
  }
}

extension Date {
  package var iso8601String: String {
    if #available(iOS 15, macOS 12, tvOS 15, watchOS 8, *) {
      return formatted(.iso8601.currentTimestamp(includingFractionalSeconds: true))
    } else {
      return DateFormatter.iso8601(includingFractionalSeconds: true).string(from: self)
    }
  }
}

extension String {
  package var date: Date? {
    if #available(iOS 15, macOS 12, tvOS 15, watchOS 8, *) {
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
    } else {
      guard
        let date = DateFormatter.iso8601(includingFractionalSeconds: true).date(from: self)
          ?? DateFormatter.iso8601(includingFractionalSeconds: false).date(from: self)
      else {
        return nil
      }
      return date
    }
  }
}
