//
//  PostgrestGeneratedColumnIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 07/10/26.
//

import Foundation
@_spi(Experimental) import PostgrestMacros
import Testing

// `Counters` is in `Generated.swift`, the table in
// `supabase/migrations/20261007000001_counters.sql`.

/// The live half of `TableIntegrationTests.aGeneratedColumnNeverReachesAWriteBody`: against a real
/// `GENERATED ALWAYS` identity key and a `GENERATED ALWAYS … STORED` column, the generated `Draft`
/// and `_PostgrestUpdate` produce writes Postgres accepts, and the generated values come back.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct PostgrestGeneratedColumnIntegrationTests {
  let client = PostgrestClient(
    url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
    headers: ["apikey": DotEnv.supabasePublishableKey]
  )

  @Test
  func insertAndUpdateLeaveTheGeneratedColumnsToTheDatabase() async throws {
    let inserted = try await client.from(Counters.self)
      .insert(Counters.Draft(count: 2)).returning().single().execute().value
    #expect(inserted.doubled == 4)

    let updated = try await client.from(Counters.self)
      .update { $0.count = 5 }.where { $0.id.eq(inserted.id) }
      .returning().single().execute().value
    #expect(updated.id == inserted.id)
    #expect(updated.doubled == 10)

    try await client.from(Counters.self).delete().where { $0.id.eq(inserted.id) }.execute()
  }
}
