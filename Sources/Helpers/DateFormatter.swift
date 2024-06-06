//
//  DateFormatter.swift
//
//
//  Created by Guilherme Souza on 28/12/23.
//

import Foundation

extension DateFormatter {
  /// DateFormatter class that generates and parses string representations of dates following the
  /// ISO 8601 standard
  package static let iso8601: DateFormatter = {
    let iso8601DateFormatter = DateFormatter()

    iso8601DateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    iso8601DateFormatter.locale = Locale(identifier: "en_US_POSIX")
    iso8601DateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    return iso8601DateFormatter
  }()

  package static let iso8601_noMilliseconds: DateFormatter = {
    let iso8601DateFormatter = DateFormatter()

    iso8601DateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
    iso8601DateFormatter.locale = Locale(identifier: "en_US_POSIX")
    iso8601DateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    return iso8601DateFormatter
  }()
}
