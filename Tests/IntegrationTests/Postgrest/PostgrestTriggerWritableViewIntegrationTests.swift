//
//  PostgrestTriggerWritableViewIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 09/10/26.
//

import Foundation
@_spi(Experimental) import PostgrestMacros
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct PostgrestTriggerWritableViewIntegrationTests {
  let client = PostgrestClient(
    url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
    headers: ["apikey": DotEnv.supabasePublishableKey]
  )

  @Test
  func insertGoesThroughTheTrigger() async throws {
    let inserted = try await client.from(NoteSummaries.self)
      .insert(NoteSummaries.Draft(body: "hello")).returning().single().execute().value
    let id = try #require(inserted.id)
    #expect(inserted.body == "hello")
    #expect(inserted.bodyLength == 5)

    try await client.from(Notes.self).delete().where { $0.id.eq(id) }.execute()
  }
}
