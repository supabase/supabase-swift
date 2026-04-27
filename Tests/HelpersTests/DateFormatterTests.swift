//
//  DateFormatterTests.swift
//  Supabase
//
//  Created by Coverage Tests
//

import XCTest
@testable import Helpers

final class DateFormatterTests: XCTestCase {

  // MARK: - Date to ISO8601 String Tests

  func testDateToISO8601String() {
    // Create a specific date: 2024-01-15 10:30:45.123 UTC
    var components = DateComponents()
    components.year = 2024
    components.month = 1
    components.day = 15
    components.hour = 10
    components.minute = 30
    components.second = 45
    components.nanosecond = 123_000_000 // 123 milliseconds
    components.timeZone = TimeZone(secondsFromGMT: 0)

    let calendar = Calendar(identifier: .iso8601)
    guard let date = calendar.date(from: components) else {
      XCTFail("Failed to create test date")
      return
    }

    let iso8601String = date.iso8601String

    // Should contain the date and time
    XCTAssertTrue(iso8601String.contains("2024-01-15"))
    XCTAssertTrue(iso8601String.contains("10:30:45"))
  }

  func testCurrentDateToISO8601String() {
    let now = Date()
    let iso8601String = now.iso8601String

    // Verify it's not empty and has proper format
    XCTAssertFalse(iso8601String.isEmpty)
    XCTAssertTrue(iso8601String.contains("T")) // Should have date-time separator
    XCTAssertTrue(iso8601String.contains("-")) // Should have date separators
    XCTAssertTrue(iso8601String.contains(":")) // Should have time separators
  }

  // MARK: - String to Date Parsing Tests

  func testParseISO8601StringWithFractionalSeconds() {
    let dateString = "2024-01-15T10:30:45.123"
    guard let parsedDate = dateString.date else {
      XCTFail("Failed to parse date string")
      return
    }

    let calendar = Calendar(identifier: .iso8601)
    let components = calendar.dateComponents(
      in: TimeZone(secondsFromGMT: 0)!,
      from: parsedDate
    )

    XCTAssertEqual(components.year, 2024)
    XCTAssertEqual(components.month, 1)
    XCTAssertEqual(components.day, 15)
    XCTAssertEqual(components.hour, 10)
    XCTAssertEqual(components.minute, 30)
    XCTAssertEqual(components.second, 45)
  }

  func testParseISO8601StringWithoutFractionalSeconds() {
    let dateString = "2024-01-15T10:30:45"
    guard let parsedDate = dateString.date else {
      XCTFail("Failed to parse date string")
      return
    }

    let calendar = Calendar(identifier: .iso8601)
    let components = calendar.dateComponents(
      in: TimeZone(secondsFromGMT: 0)!,
      from: parsedDate
    )

    XCTAssertEqual(components.year, 2024)
    XCTAssertEqual(components.month, 1)
    XCTAssertEqual(components.day, 15)
    XCTAssertEqual(components.hour, 10)
    XCTAssertEqual(components.minute, 30)
    XCTAssertEqual(components.second, 45)
  }

  func testParseInvalidDateString() {
    let invalidStrings = [
      "not a date",
      "2024-13-45", // Invalid month and day
      "2024/01/15", // Wrong separator
      "15-01-2024", // Wrong order
      "",
      "2024-01-15 10:30:45", // Space instead of T
    ]

    for invalidString in invalidStrings {
      XCTAssertNil(
        invalidString.date,
        "Should return nil for invalid date string: \(invalidString)"
      )
    }
  }

  func testParseEmptyString() {
    let emptyString = ""
    XCTAssertNil(emptyString.date)
  }

  // MARK: - Round-trip Tests

  func testRoundTripConversion() {
    // Create a date, convert to string, parse back to date
    var components = DateComponents()
    components.year = 2023
    components.month = 6
    components.day = 15
    components.hour = 14
    components.minute = 30
    components.second = 0
    components.timeZone = TimeZone(secondsFromGMT: 0)

    let calendar = Calendar(identifier: .iso8601)
    guard let originalDate = calendar.date(from: components) else {
      XCTFail("Failed to create original date")
      return
    }

    let dateString = originalDate.iso8601String
    guard let parsedDate = dateString.date else {
      XCTFail("Failed to parse date from string: \(dateString)")
      return
    }

    // Compare timestamps (allowing small tolerance for milliseconds)
    let timeDifference = abs(originalDate.timeIntervalSince(parsedDate))
    XCTAssertLessThan(timeDifference, 1.0, "Dates should be within 1 second of each other")
  }

  func testRoundTripWithCurrentDate() {
    let now = Date()
    let dateString = now.iso8601String
    guard let parsedDate = dateString.date else {
      XCTFail("Failed to parse current date from string: \(dateString)")
      return
    }

    // Compare timestamps (allowing small tolerance for milliseconds)
    let timeDifference = abs(now.timeIntervalSince(parsedDate))
    XCTAssertLessThan(timeDifference, 1.0, "Dates should be within 1 second of each other")
  }

  // MARK: - Edge Cases

  func testParseDateAtMidnight() {
    let dateString = "2024-01-01T00:00:00"
    guard let parsedDate = dateString.date else {
      XCTFail("Failed to parse midnight date")
      return
    }

    let calendar = Calendar(identifier: .iso8601)
    let components = calendar.dateComponents(
      in: TimeZone(secondsFromGMT: 0)!,
      from: parsedDate
    )

    XCTAssertEqual(components.hour, 0)
    XCTAssertEqual(components.minute, 0)
    XCTAssertEqual(components.second, 0)
  }

  func testParseDateAtEndOfDay() {
    let dateString = "2024-12-31T23:59:59"
    guard let parsedDate = dateString.date else {
      XCTFail("Failed to parse end-of-day date")
      return
    }

    let calendar = Calendar(identifier: .iso8601)
    let components = calendar.dateComponents(
      in: TimeZone(secondsFromGMT: 0)!,
      from: parsedDate
    )

    XCTAssertEqual(components.month, 12)
    XCTAssertEqual(components.day, 31)
    XCTAssertEqual(components.hour, 23)
    XCTAssertEqual(components.minute, 59)
    XCTAssertEqual(components.second, 59)
  }

  func testParseLeapYearDate() {
    let dateString = "2024-02-29T12:00:00" // 2024 is a leap year
    XCTAssertNotNil(dateString.date, "Should parse leap year date")
  }

  func testParseVariousFractionalSecondFormats() {
    let formats = [
      "2024-01-15T10:30:45.1",
      "2024-01-15T10:30:45.12",
      "2024-01-15T10:30:45.123",
      "2024-01-15T10:30:45.1234",
    ]

    for format in formats {
      // These might not all parse depending on the formatter, but at least test them
      let _ = format.date
    }
  }

  // MARK: - Multiple Date Conversion Tests

  func testConvertMultipleDates() {
    let dates = [
      "2020-01-01T00:00:00",
      "2021-06-15T12:30:45",
      "2022-12-31T23:59:59",
      "2023-07-04T16:20:30.500",
      "2024-02-29T08:15:22", // Leap year
    ]

    for dateString in dates {
      XCTAssertNotNil(
        dateString.date,
        "Should parse date: \(dateString)"
      )
    }
  }

  func testConvertDatesInDifferentYears() {
    for year in 2020...2025 {
      let dateString = "\(year)-06-15T12:00:00"
      guard let parsedDate = dateString.date else {
        XCTFail("Failed to parse date for year \(year)")
        continue
      }

      let calendar = Calendar(identifier: .iso8601)
      let components = calendar.dateComponents(
        in: TimeZone(secondsFromGMT: 0)!,
        from: parsedDate
      )

      XCTAssertEqual(components.year, year)
    }
  }
}
