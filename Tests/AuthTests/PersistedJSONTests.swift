import Foundation
import Testing

@testable import Auth

/// 2026-09-22T10:42:45Z.
private let reference: TimeInterval = 811_766_565

@Suite
struct PersistedJSONTests {
  @Test(arguments: [
    ("2026-09-22T10:42:45Z", reference),
    ("2026-09-22t10:42:45z", reference),
    ("2026-09-22T10:42:45.5Z", reference + 0.5),
    ("2026-09-22T10:42:45.123Z", reference + 0.123),
    ("2026-09-22T10:42:45.123456Z", reference + 0.123_456),
    ("2026-09-22T10:42:45.123456789Z", reference + 0.123_456_789),
    ("2026-09-22T12:42:45+02:00", reference),
    ("2026-09-22T12:42:45+0200", reference),
    ("2026-09-22T12:42:45+02", reference),
    ("2026-09-22T05:12:45.25-05:30", reference + 0.25),
    ("2026-09-23T00:42:45+14:00", reference),
  ])
  func readsRFC3339(_ string: String, expected: TimeInterval) {
    #expect(PersistedJSON.date(from: string) == Date(timeIntervalSinceReferenceDate: expected))
  }

  @Test(arguments: [
    "2026-09-22T10:42:45",
    "2026-09-22T10:42:45.Z",
    "2026-09-22T10:42:45.1234567890Z",
    "2026-09-22 10:42:45Z",
    "2026-09-22T10:42:45Zjunk",
    "2026-02-29T10:42:45Z",
    "2026-13-01T10:42:45Z",
    "2026-09-22T24:00:00Z",
    "2026-09-22T10:42:45+2:00",
    "2026-09-22",
    "",
  ])
  func rejectsMalformedTimestamps(_ string: String) {
    #expect(PersistedJSON.date(from: string) == nil)
  }

  @Test(arguments: [
    (reference, "2026-09-22T10:42:45Z"),
    (reference + 0.5, "2026-09-22T10:42:45.5Z"),
    (reference + 0.25, "2026-09-22T10:42:45.25Z"),
    (-978_307_201.5, "1969-12-31T23:59:58.5Z"),
    (0, "2001-01-01T00:00:00Z"),
    (-31_622_400, "2000-01-01T00:00:00Z"),
  ])
  func writesUTC(_ interval: TimeInterval, expected: String) {
    #expect(
      PersistedJSON.timestamp(from: Date(timeIntervalSinceReferenceDate: interval)) == expected
    )
  }

  @Test
  func timestampsRoundTripExactly() {
    var dates = [Date(), Date.distantPast, Date.distantFuture]
    for step in 0..<10_000 {
      dates.append(
        Date(timeIntervalSinceReferenceDate: Double(step) * 98_765.432_109_876_5 + 32_000_000)
      )
    }

    for date in dates {
      let string = PersistedJSON.timestamp(from: date)
      #expect(PersistedJSON.date(from: string) == date, "\(string)")
    }
  }
}
