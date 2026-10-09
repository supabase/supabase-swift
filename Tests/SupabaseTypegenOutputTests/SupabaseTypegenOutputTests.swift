//
//  SupabaseTypegenOutputTests.swift
//  SupabaseTypegenOutputTests
//
//  Created by Guilherme Souza on 09/10/26.
//

import Foundation
import HTTPTypes
@_spi(Experimental) import PostgrestMacros
import TestHelpers
import Testing

// `Generated.swift` is `supabase-typegen --access-control public` run on the integration schema.
// These tests use it the way an app would.

@SelectionOf(Channels.self)
struct ChannelFeed {
  var slug: String
  var shoutedSlug: String?
  @Relationship(computed: \Channels.Columns.channelMessages) var messages: [Messages]
  @Relationship(computed: \Channels.Columns.firstMessage) var first: Messages?
}

/// A client whose requests are recorded, answering each with `body`.
func recordingClient(body: String = "[]") -> (PostgrestClient, RecordingTransport) {
  let transport = RecordingTransport { _, _ in
    (HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]), Data(body.utf8))
  }
  let client = PostgrestClient(
    url: URL(string: "https://example.supabase.co")!,
    http: .init(transport: transport)
  )
  return (client, transport)
}

@Suite
struct SupabaseTypegenOutputTests {
  @Test
  func relationNameIsTheTableName() {
    #expect(Users.relationName == "users")
    #expect(KeyValueStorage.relationName == "key_value_storage")
  }

  @Test
  func snakeCaseColumnKeepsItsName() {
    #expect(Posts.columns.discussionId.postgrestExpression == "discussion_id")
    #expect(Todos.columns.isComplete.postgrestExpression == "is_complete")
  }

  @Test
  func draftLeavesOutAnAlwaysIdentityColumn() async throws {
    #expect(Mirror(reflecting: Counters.Draft(count: 1)).children.map(\.label) == ["count"])

    let (client, transport) = recordingClient()
    _ = try await client.from(Counters.self).insert(Counters.Draft(count: 1)).execute()
    #expect(
      transport.requests.first?.body.map { String(decoding: $0, as: UTF8.self) } == #"{"count":1}"#)
  }

  @Test
  func generatedEnumIsAFilterOperand() async throws {
    let (client, transport) = recordingClient(
      body: #"[{"id":"7c1f0f4e-5d3b-4b8e-9d8a-1b2c3d4e5f60","status":"OFFLINE"}]"#
    )
    let rows = try await client.from(Users.self).select()
      .where { $0.status.eq(.online) || $0.status.in([.offline]) }
      .execute().value

    #expect(
      transport.requests.first?.head.path?.removingPercentEncoding
        == "/users?select=*&or=(status.eq.ONLINE,status.in.(OFFLINE))"
    )
    #expect(rows.map(\.status) == [.offline])
  }

  @Test
  func computedFieldAndRelationshipsInASelection() async throws {
    #expect(
      ChannelFeed.selectString
        == "slug:slug,shouted_slug:shouted_slug,messages:channel_messages(*),"
        + "first:first_message(*)"
    )

    let (client, transport) = recordingClient()
    _ = try await client.from(Channels.self).select(ChannelFeed.self)
      .where { $0.shoutedSlug.eq("GENERAL") }
      .execute()
    #expect(
      transport.requests.first?.head.path?.removingPercentEncoding
        == "/channels?select=slug:slug,shouted_slug:shouted_slug,"
        + "messages:channel_messages(*),first:first_message(*)&shouted_slug=eq.GENERAL"
    )
  }
}
