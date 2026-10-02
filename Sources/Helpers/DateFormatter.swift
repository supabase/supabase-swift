//
//  DateFormatter.swift
//
//
//  Created by Guilherme Souza on 28/12/23.
//

package import Foundation

extension Date.ISO8601FormatStyle {
  fileprivate func currentTimestamp(includingFractionalSeconds: Bool) -> Self {
    year().month().day()
      .dateTimeSeparator(.standard)
      .time(includingFractionalSeconds: includingFractionalSeconds)
  }

  /// Same as ``currentTimestamp(includingFractionalSeconds:)``, but also parses a UTC offset
  /// (`timestamptz`'s wire format), so e.g. `+02:00`/`+0200`/`+02`/`Z` apply instead of being
  /// silently dropped.
  fileprivate func currentTimestampWithOffset(includingFractionalSeconds: Bool) -> Self {
    currentTimestamp(includingFractionalSeconds: includingFractionalSeconds)
      .timeZone(separator: .colon)
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
      strategy: .iso8601.currentTimestampWithOffset(includingFractionalSeconds: true)
    ) {
      return date
    }
    if let date = try? Date(
      self,
      strategy: .iso8601.currentTimestampWithOffset(includingFractionalSeconds: false)
    ) {
      return date
    }
    // No offset in the string, e.g. a `timestamp` (without time zone) column: read it as UTC.
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
