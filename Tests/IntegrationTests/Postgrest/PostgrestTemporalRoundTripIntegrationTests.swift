//
//  PostgrestTemporalRoundTripIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 09/10/26.
//

import Foundation
import PostgrestMacros
import Testing

// File scope: `@SelectionOf` attaches extensions, which cannot be nested in a type.
// `TemporalValues` is in `Generated.swift`, the table in
// `supabase/migrations/20261009000000_temporal_values.sql`.

@SelectionOf(TemporalValues.self)
struct TemporalTimestamps {
  var atInstant: Date
  var atLocal: Date
}

/// supabase-typegen maps `timestamptz`, `timestamp` and `date` to `Date`. These tests write each
/// through the generated `Draft` and read it back from a live PostgREST.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct PostgrestTemporalRoundTripIntegrationTests {
  let client = PostgrestClient(
    url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
    headers: ["apikey": DotEnv.supabasePublishableKey]
  )

  /// Whole seconds: Postgres keeps microseconds, the encoder writes milliseconds. Random, so
  /// filtering on it finds this test's row only.
  let instant = Date(timeIntervalSince1970: TimeInterval(Int.random(in: 0..<2_000_000_000)))

  /// Midnight UTC of `instant`: the encoder writes UTC, and a `date` column keeps the day only.
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

  /// `timestamptz` comes back with an offset, `timestamp` without one; both read as the same
  /// instant, because the encoder writes UTC and the decoder reads an offset-less value as UTC.
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

  /// Postgres reads the encoder's full timestamp as its day, and PostgREST sends the day back with
  /// no time (`2026-10-09`), which the decoder reads as midnight UTC.
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
