import Foundation
import Testing

@testable import Auth

@Suite
struct PersistedJSONTests {
  private struct Stamped: Codable, Equatable {
    var date: Date
  }

  @Test
  func writesDatesAsSecondsSinceTheReferenceDate() throws {
    // 2026-09-22T10:42:45.5Z
    let data = try PersistedJSON.encoder.encode(
      Stamped(date: Date(timeIntervalSince1970: 1_790_073_765.5))
    )

    #expect(String(decoding: data, as: UTF8.self) == #"{"date":811766565.5}"#)
  }

  @Test
  func datesRoundTripExactly() throws {
    var dates = [Date(), Date.distantPast, Date.distantFuture]
    for step in 0..<10_000 {
      dates.append(
        Date(timeIntervalSinceReferenceDate: Double(step) * 98_765.432_109_876_5 + 32_000_000)
      )
    }

    for date in dates {
      let data = try PersistedJSON.encoder.encode(Stamped(date: date))
      #expect(try PersistedJSON.decoder.decode(Stamped.self, from: data).date == date)
    }
  }
}
