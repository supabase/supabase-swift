//
//  PostgresValuesIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 10/10/26.
//

import Foundation
@_spi(Experimental) import PostgrestMacros
import Testing

// `PostgresValues` is in `Generated.swift`, the table in
// `supabase/migrations/20261010000000_postgres_values.sql`.

/// Each `_Postgres…` type the generator emits, written through the generated `Draft`, read back,
/// and filtered on, against a live PostgREST.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct PostgresValuesIntegrationTests {
  let client = PostgrestClient(
    url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
    headers: ["apikey": DotEnv.supabasePublishableKey]
  )

  @Test
  func everyTypeRoundTripsAndFilters() async throws {
    var draft = PostgresValues.Draft()
    draft.intSpan = "[1,10)"
    draft.daySpan = "[2024-01-01,2024-01-31]"
    draft.duration = "P1DT2H"
    draft.atTime = "13:45:00"
    draft.atTimeTz = "13:45:00+02"
    draft.payload = _PostgresBytes(Data([0xde, 0xad, 0xbe, 0xef]))
    draft.address = "192.168.0.1/24"
    draft.price = "12.34"
    draft.pair = _PostgresUnmapped(["amount": 1, "currency": "USD"])
    draft.spot = _PostgresUnmapped("(1,2)")
    let row = try await client.from(PostgresValues.self)
      .insert(draft).returning().single().execute().value

    // Each comes back in the server's own text form.
    #expect(row.intSpan == "[1,10)")
    #expect(row.daySpan == "[2024-01-01,2024-02-01)")
    #expect(row.duration == "1 day 02:00:00")
    #expect(row.atTime == "13:45:00")
    #expect(row.payload == _PostgresBytes(Data([0xde, 0xad, 0xbe, 0xef])))
    #expect(row.price == "$12.34")
    #expect(row.pair == _PostgresUnmapped(["amount": 1, "currency": "USD"]))
    #expect(row.spot == _PostgresUnmapped("(1,2)"))

    func matches(
      _ filter: (PostgresValues.Columns) -> _PostgrestFilter<PostgresValues>
    ) async throws -> Bool {
      try await !client.from(PostgresValues.self).select()
        .where { $0.id.eq(row.id) && filter($0) }
        .execute().value.isEmpty
    }

    #expect(try await matches { $0.intSpan.containsRange("[2,3)") })
    #expect(try await matches { $0.intSpan.eq("[1,10)") })
    #expect(try await matches { $0.daySpan.overlapsRange("[2024-01-15,2024-03-01)") })
    #expect(try await matches { $0.duration.eq("26:00:00") })
    #expect(try await matches { $0.duration.gt("1 day") })
    #expect(try await matches { $0.atTime.gt("12:00") })
    #expect(try await matches { $0.atTimeTz.eq("11:45:00+00") } == false)
    #expect(try await matches { $0.payload.eq(_PostgresBytes(Data([0xde, 0xad, 0xbe, 0xef]))) })
    #expect(try await matches { $0.address.eq("192.168.0.1/24") })
    // Inside a group each operand is quoted, which a range and a `bytea` need there.
    #expect(
      try await matches {
        $0.intSpan.eq("[0,1)") || $0.payload.eq(_PostgresBytes(Data([0xde, 0xad, 0xbe, 0xef])))
      })
    #expect(
      try await matches {
        $0.duration.in(["1 day 02:00:00", "-1 days"]) && $0.intSpan.eq("[1,10)")
      })

    try await client.from(PostgresValues.self).delete().where { $0.id.eq(row.id) }.execute()
  }
}
