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
  /// (`timestamptz`'s wire format).
  fileprivate func currentTimestampWithOffset(includingFractionalSeconds: Bool) -> Self {
    currentTimestamp(includingFractionalSeconds: includingFractionalSeconds)
      .timeZone(separator: .colon)
  }
}

extension Date {
  package var iso8601String: String {
    formatted(.iso8601.currentTimestampWithOffset(includingFractionalSeconds: true))
  }
}

extension String {
  package var date: Date? {
    let normalized = Self.normalizingTimestampOffset(self)
    if let date = try? Date(
      normalized,
      strategy: .iso8601.currentTimestampWithOffset(includingFractionalSeconds: true)
    ) {
      return date
    }
    if let date = try? Date(
      normalized,
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
    if let date = try? Date(
      self,
      strategy: .iso8601.currentTimestamp(includingFractionalSeconds: false)
    ) {
      return date
    }
    // A `date` column: the day only, read as midnight UTC. Parsing accepts a trailing remainder,
    // so the value must format back to the whole string.
    let day: Date.ISO8601FormatStyle = .iso8601.year().month().day()
    guard let date = try? Date(self, strategy: day), date.formatted(day) == self else {
      return nil
    }
    return date
  }

  /// Rewrites a Postgres timestamp's UTC offset into the canonical `+HH:MM` form that
  /// `ISO8601FormatStyle(timeZone: .colon)` parses consistently on every Foundation version, e.g.
  /// `Z` -> `+00:00`, `+0200` -> `+02:00`, `+02` -> `+02:00`. The abbreviated spellings are
  /// syntactically valid ISO 8601 but parsed leniently on some Foundation versions and not others
  /// (SDK-2090's CI caught this on the Xcode 26.0 toolchain this SDK still tests against), while
  /// the canonical colon form parses — and has its offset actually applied — everywhere.
  ///
  /// Leaves a `timestamp` (without time zone) value, which has no offset, unchanged; actually
  /// applying the (normalized) offset is still Foundation's job, via `.timeZone(separator: .colon)`.
  private static func normalizingTimestampOffset(_ string: String) -> String {
    if string.hasSuffix("Z") {
      return string.dropLast() + "+00:00"
    }
    guard
      let timeSeparator = string.firstIndex(of: "T"),
      let signIndex = string[timeSeparator...].lastIndex(where: { $0 == "+" || $0 == "-" })
    else {
      return string
    }
    let digits = string[string.index(after: signIndex)...].filter(\.isNumber)
    guard digits.count == 2 || digits.count == 4 else {
      return string
    }
    let hours = digits.prefix(2)
    let minutes = digits.count == 4 ? digits.suffix(2) : "00"
    return "\(string[..<signIndex])\(string[signIndex])\(hours):\(minutes)"
  }
}
