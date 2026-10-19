//
//  PostgrestComputedMemberIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 08/10/26.
//

import Foundation
@_spi(Experimental) import PostgrestMacros
import Testing

@SelectionOf(Channels.self)
struct ComputedMemberChannelFeed {
  var id: Int
  var shoutedSlug: String?
  @Relationship(computed: \Channels.Columns.channelMessages)
  var messages: [Messages]
  @Relationship(computed: \Channels.Columns.firstMessage)
  var first: Messages?
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct PostgrestComputedMemberIntegrationTests {
  let client = PostgrestClient(
    url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
    headers: ["apikey": DotEnv.supabasePublishableKey]
  )

  @Test
  func aWholeRowSelectReturnsNoComputedMember() async throws {
    let response = try await client.from(Channels.self)
      .select()
      .order { $0.id }
      .execute()

    #expect(response.value.map(\.slug) == ["public", "random"])
    let rows = try JSONSerialization.jsonObject(with: response.data) as? [[String: Any]]
    #expect(rows?.map { Set($0.keys) } == [["id", "slug"], ["id", "slug"]])
  }

  @Test
  func aComputedFieldAndComputedRelationshipsDecode() async throws {
    let rows = try await client.from(Channels.self)
      .select(ComputedMemberChannelFeed.self)
      .where { $0.shoutedSlug.eq("PUBLIC") }
      .execute()
      .value

    #expect(rows.map(\.shoutedSlug) == ["PUBLIC"])
    #expect(rows.first?.messages.map(\.id) == [1])
    #expect(rows.first?.first?.message == "Hello World 👋")
  }

  @Test
  func requiringAComputedRelationshipDropsParentsWithNoMatch() async throws {
    let rows = try await client.from(Channels.self)
      .select(ComputedMemberChannelFeed.self)
      .order { $0.shoutedSlug.desc() }
      .requiring(\.messages) { $0.where { $0.id.eq(2) } }
      .execute()
      .value

    #expect(rows.map(\.id) == [2])
  }
}
