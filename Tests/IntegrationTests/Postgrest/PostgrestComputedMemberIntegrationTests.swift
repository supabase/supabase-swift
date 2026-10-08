//
//  PostgrestComputedMemberIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 08/10/26.
//

import Foundation
import PostgrestMacros
import Testing

// File scope: `@Table` and `@SelectionOf` attach extensions, which cannot be nested in a type.
// The functions are in `supabase/migrations/20261008000000_computed_members.sql`, the rows in
// `supabase/seed.sql`. Every test here is read-only.

@Table("channels")
struct ComputedMemberChannel {
  @PrimaryKey @Default var id: Int
  var slug: String
}

@Table("messages")
struct ComputedMemberMessage {
  @PrimaryKey @Default var id: Int
  var channelID: Int?
  var message: String?
}

extension ComputedMemberChannel.Columns {
  var shoutedSlug: PostgrestComputedField<ComputedMemberChannel, String> { .init("shouted_slug") }
  var channelMessages: PostgrestToManyRelation<ComputedMemberChannel, ComputedMemberMessage> {
    .init("channel_messages")
  }
  var firstMessage: PostgrestToOneRelation<ComputedMemberChannel, ComputedMemberMessage> {
    .init("first_message")
  }
}

@SelectionOf(ComputedMemberChannel.self)
struct ComputedMemberChannelFeed {
  var id: Int
  var shoutedSlug: String?
  @Relationship(computed: \ComputedMemberChannel.Columns.channelMessages)
  var messages: [ComputedMemberMessage]
  @Relationship(computed: \ComputedMemberChannel.Columns.firstMessage)
  var first: ComputedMemberMessage?
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct PostgrestComputedMemberIntegrationTests {
  let client = PostgrestClient(
    url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
    headers: ["apikey": DotEnv.supabasePublishableKey]
  )

  /// `ComputedMemberChannel` decodes only `id` and `slug`, so this also proves `*` is exactly the
  /// two columns: the response's keys are asserted, not just decodable.
  @Test
  func aWholeRowSelectReturnsNoComputedMember() async throws {
    let response = try await client.from(ComputedMemberChannel.self)
      .select()
      .order { $0.id }
      .execute()

    #expect(response.value.map(\.slug) == ["public", "random"])
    let rows = try JSONSerialization.jsonObject(with: response.data) as? [[String: Any]]
    #expect(rows?.map { Set($0.keys) } == [["id", "slug"], ["id", "slug"]])
  }

  @Test
  func aComputedFieldAndComputedRelationshipsDecode() async throws {
    let rows = try await client.from(ComputedMemberChannel.self)
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
    let rows = try await client.from(ComputedMemberChannel.self)
      .select(ComputedMemberChannelFeed.self)
      .order { $0.shoutedSlug.desc() }
      .requiring(\.messages) { $0.where { $0.id.eq(2) } }
      .execute()
      .value

    #expect(rows.map(\.id) == [2])
  }
}
