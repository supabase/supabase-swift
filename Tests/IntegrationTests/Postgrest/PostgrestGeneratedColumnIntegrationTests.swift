//
//  PostgrestGeneratedColumnIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 07/10/26.
//

import Foundation
import PostgrestMacros
import Testing

// File scope: `@Table` attaches an extension, which cannot be nested in a type. The table is in
// `supabase/migrations/20261007000001_counters.sql`.

@Table("counters")
struct Counter {
  @PrimaryKey @Generated var id: Int
  var count: Int
  @Generated var doubled: Int
}

/// The live half of `TableIntegrationTests.aGeneratedColumnNeverReachesAWriteBody`: against a real
/// `GENERATED ALWAYS` identity key and a `GENERATED ALWAYS … STORED` column, the generated `Draft`
/// and `PostgrestUpdate` produce writes Postgres accepts, and the generated values come back.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct PostgrestGeneratedColumnIntegrationTests {
  let client = PostgrestClient(
    url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
    headers: ["apikey": DotEnv.supabasePublishableKey]
  )

  @Test
  func insertAndUpdateLeaveTheGeneratedColumnsToTheDatabase() async throws {
    let inserted = try await client.from(Counter.self)
      .insert(Counter.Draft(count: 2)).returning().single().execute().value
    #expect(inserted.doubled == 4)

    let updated = try await client.from(Counter.self)
      .update { $0.count = 5 }.where { $0.id.eq(inserted.id) }
      .returning().single().execute().value
    #expect(updated.id == inserted.id)
    #expect(updated.doubled == 10)

    try await client.from(Counter.self).delete().where { $0.id.eq(inserted.id) }.execute()
  }
}
