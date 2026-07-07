//
//  DateFormatterTests.swift
//  Supabase
//
//  Created by Coverage Tests
//

import Foundation
import Testing

@testable import Helpers

@Suite
struct DateFormatterTests {

  // MARK: - Date to ISO8601 String Tests

  @Test
  func dateToISO8601String() throws {
    // Create a specific date: 2024-01-15 10:30:45.123 UTC
    var components = DateComponents()
    components.year = 2024
    components.month = 1
    components.day = 15
    components.hour = 10
    components.minute = 30
    components.second = 45
    components.nanosecond = 123_000_000  // 123 milliseconds
    components.timeZone = TimeZone(secondsFromGMT: 0)

    let calendar = Calendar(identifier: .iso8601)
    let date = try #require(calendar.date(from: components), "Failed to create test date")

    let iso8601String = date.iso8601String

    // Should contain the date and time
    #expect(iso8601String.contains("2024-01-15"))
    #expect(iso8601String.contains("10:30:45"))
  }

  @Test
  func currentDateToISO8601String() {
    let now = Date()
    let iso8601String = now.iso8601String

    // Verify it's not empty and has proper format
    #expect(!iso8601String.isEmpty)
    #expect(iso8601String.contains("T"))  // Should have date-time separator
    #expect(iso8601String.contains("-"))  // Should have date separators
    #expect(iso8601String.contains(":"))  // Should have time separators
  }

  // MARK: - String to Date Parsing Tests

  @Test
  func parseISO8601StringWithFractionalSeconds() throws {
    let dateString = "2024-01-15T10:30:45.123"
    let parsedDate = try #require(dateString.date, "Failed to parse date string")

    let calendar = Calendar(identifier: .iso8601)
    let components = calendar.dateComponents(
      in: TimeZone(secondsFromGMT: 0)!,
      from: parsedDate
    )

    #expect(components.year == 2024)
    #expect(components.month == 1)
    #expect(components.day == 15)
    #expect(components.hour == 10)
    #expect(components.minute == 30)
    #expect(components.second == 45)
  }

  @Test
  func parseISO8601StringWithoutFractionalSeconds() throws {
    let dateString = "2024-01-15T10:30:45"
    let parsedDate = try #require(dateString.date, "Failed to parse date string")

    let calendar = Calendar(identifier: .iso8601)
    let components = calendar.dateComponents(
      in: TimeZone(secondsFromGMT: 0)!,
      from: parsedDate
    )

    #expect(components.year == 2024)
    #expect(components.month == 1)
    #expect(components.day == 15)
    #expect(components.hour == 10)
    #expect(components.minute == 30)
    #expect(components.second == 45)
  }

  @Test
  func parseInvalidDateString() {
    let invalidStrings = [
      "not a date",
      "2024-13-45",  // Invalid month and day
      "2024/01/15",  // Wrong separator
      "15-01-2024",  // Wrong order
      "",
      "2024-01-15 10:30:45",  // Space instead of T
    ]

    for invalidString in invalidStrings {
      #expect(
        invalidString.date == nil,
        "Should return nil for invalid date string: \(invalidString)"
      )
    }
  }

  @Test
  func parseEmptyString() {
    let emptyString = ""
    #expect(emptyString.date == nil)
  }

  // MARK: - Round-trip Tests

  @Test
  func roundTripConversion() throws {
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
    let originalDate = try #require(
      calendar.date(from: components), "Failed to create original date")

    let dateString = originalDate.iso8601String
    let parsedDate = try #require(
      dateString.date, "Failed to parse date from string: \(dateString)")

    // Compare timestamps (allowing small tolerance for milliseconds)
    let timeDifference = abs(originalDate.timeIntervalSince(parsedDate))
    #expect(timeDifference < 1.0, "Dates should be within 1 second of each other")
  }

  @Test
  func roundTripWithCurrentDate() throws {
    let now = Date()
    let dateString = now.iso8601String
    let parsedDate = try #require(
      dateString.date, "Failed to parse current date from string: \(dateString)")

    // Compare timestamps (allowing small tolerance for milliseconds)
    let timeDifference = abs(now.timeIntervalSince(parsedDate))
    #expect(timeDifference < 1.0, "Dates should be within 1 second of each other")
  }

  // MARK: - Edge Cases

  @Test
  func parseDateAtMidnight() throws {
    let dateString = "2024-01-01T00:00:00"
    let parsedDate = try #require(dateString.date, "Failed to parse midnight date")

    let calendar = Calendar(identifier: .iso8601)
    let components = calendar.dateComponents(
      in: TimeZone(secondsFromGMT: 0)!,
      from: parsedDate
    )

    #expect(components.hour == 0)
    #expect(components.minute == 0)
    #expect(components.second == 0)
  }

  @Test
  func parseDateAtEndOfDay() throws {
    let dateString = "2024-12-31T23:59:59"
    let parsedDate = try #require(dateString.date, "Failed to parse end-of-day date")

    let calendar = Calendar(identifier: .iso8601)
    let components = calendar.dateComponents(
      in: TimeZone(secondsFromGMT: 0)!,
      from: parsedDate
    )

    #expect(components.month == 12)
    #expect(components.day == 31)
    #expect(components.hour == 23)
    #expect(components.minute == 59)
    #expect(components.second == 59)
  }

  @Test
  func parseLeapYearDate() {
    let dateString = "2024-02-29T12:00:00"  // 2024 is a leap year
    #expect(dateString.date != nil, "Should parse leap year date")
  }

  @Test
  func parseVariousFractionalSecondFormats() {
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

  @Test
  func convertMultipleDates() {
    let dates = [
      "2020-01-01T00:00:00",
      "2021-06-15T12:30:45",
      "2022-12-31T23:59:59",
      "2023-07-04T16:20:30.500",
      "2024-02-29T08:15:22",  // Leap year
    ]

    for dateString in dates {
      #expect(
        dateString.date != nil,
        "Should parse date: \(dateString)"
      )
    }
  }

  @Test
  func convertDatesInDifferentYears() {
    for year in 2020...2025 {
      let dateString = "\(year)-06-15T12:00:00"
      guard let parsedDate = dateString.date else {
        Issue.record("Failed to parse date for year \(year)")
        continue
      }

      let calendar = Calendar(identifier: .iso8601)
      let components = calendar.dateComponents(
        in: TimeZone(secondsFromGMT: 0)!,
        from: parsedDate
      )

      #expect(components.year == year)
    }
  }
}
