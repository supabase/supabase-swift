//
//  PostgrestTemporalRoundTripIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 09/10/26.
//

import Foundation
@_spi(Experimental) import PostgrestMacros
import Testing

@SelectionOf(TemporalValues.self)
struct TemporalTimestamps {
  var atInstant: Date
  var atLocal: Date
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct PostgrestTemporalRoundTripIntegrationTests {
  let client = PostgrestClient(
    url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
    headers: ["apikey": DotEnv.supabasePublishableKey]
  )

  let instant = Date(timeIntervalSince1970: TimeInterval(Int.random(in: 0..<2_000_000_000)))

  var day: Date {
    Date(timeIntervalSince1970: (instant.timeIntervalSince1970 / 86_400).rounded(.down) * 86_400)
  }

  private func insertRow() async throws {
    try await client.from(TemporalValues.self)
      .insert(TemporalValues.Draft(atInstant: instant, atLocal: instant, onDay: day))
      .execute()
  }

  private func deleteRow() async throws {
    try await client.from(TemporalValues.self).delete().where { $0.atInstant.eq(instant) }.execute()
  }

  @Test
  func timestamptzAndTimestampRoundTrip() async throws {
    try await insertRow()

    let row = try await client.from(TemporalValues.self)
      .select(TemporalTimestamps.self)
      .where { $0.atInstant.eq(instant) }
      .single()
      .execute()
      .value

    #expect(row.atInstant == instant)
    #expect(row.atLocal == instant)
    try await deleteRow()
  }

  @Test
  func dateRoundTrip() async throws {
    try await insertRow()

    let days: [[String: String]] = try await client.from("temporal_values")
      .select("on_day")
      .eq("at_instant", value: instant)
      .execute()
      .value
    #expect(days == [["on_day": String(day.ISO8601Format().prefix(10))]])

    let row = try await client.from(TemporalValues.self)
      .select()
      .where { $0.atInstant.eq(instant) }
      .single()
      .execute()
      .value
    #expect(row.onDay == day)
    try await deleteRow()
  }
}
