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
}

extension Date {
  package var iso8601String: String {
    formatted(.iso8601.currentTimestamp(includingFractionalSeconds: true))
  }
}

extension String {
  package var date: Date? {
    let (body, offsetSeconds) = Self.splitPostgresTimestampOffset(self)

    let date =
      (try? Date(body, strategy: .iso8601.currentTimestamp(includingFractionalSeconds: true)))
      ?? (try? Date(body, strategy: .iso8601.currentTimestamp(includingFractionalSeconds: false)))
    guard let date, let offsetSeconds else { return date }
    return date.addingTimeInterval(-offsetSeconds)
  }

  /// Splits a Postgres timestamp wire value into its offset-less body and its UTC offset in
  /// seconds, e.g. `timestamptz`'s `2024-01-02T03:04:05+02:00` -> (`"2024-01-02T03:04:05"`, 7200).
  ///
  /// `ISO8601FormatStyle`'s own offset parsing (`+02:00`/`+0200`/`+02`/`Z`) is lenient on some
  /// Foundation versions and not others (SDK-2090's CI caught this on the Xcode 26.0 toolchain
  /// this SDK still tests against), so the offset is parsed here instead, with plain string
  /// slicing that behaves the same on every version.
  ///
  /// Returns a `nil` offset for a `timestamp` (without time zone) value, which has none.
  private static func splitPostgresTimestampOffset(
    _ string: String
  ) -> (body: Substring, offsetSeconds: TimeInterval?) {
    if string.hasSuffix("Z") {
      return (string.dropLast(), 0)
    }
    guard
      let timeSeparator = string.firstIndex(of: "T"),
      let signIndex = string[timeSeparator...].lastIndex(where: { $0 == "+" || $0 == "-" })
    else {
      return (Substring(string), nil)
    }
    let digits = string[string.index(after: signIndex)...].filter(\.isNumber)
    guard digits.count == 2 || digits.count == 4, let hours = Int(digits.prefix(2)) else {
      return (Substring(string), nil)
    }
    let minutes = digits.count == 4 ? Int(digits.suffix(2)) ?? 0 : 0
    let magnitude = TimeInterval(hours * 3_600 + minutes * 60)
    return (string[..<signIndex], string[signIndex] == "-" ? -magnitude : magnitude)
  }
}
