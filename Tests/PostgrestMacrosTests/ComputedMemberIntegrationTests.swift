//
//  ComputedMemberIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 08/10/26.
//

import Foundation
import PostgrestMacros
import Testing

// File scope, for the same reason as `SelectionIntegrationTests`: both macros attach extensions.

@Table("users")
struct ComputedUser {
  @PrimaryKey var id: Int
  var firstName: String
  var lastName: String
}

extension ComputedUser.Columns {
  var fullName: PostgrestComputedField<ComputedUser, String> { .init("full_name") }
}

@Table("channels")
struct ComputedChannel {
  @PrimaryKey var id: Int
  var slug: String
}

@Table("messages")
struct ComputedMessage {
  @PrimaryKey var id: Int
  var channelID: Int
  var body: String
}

extension ComputedChannel.Columns {
  var getMessages: PostgrestToManyRelation<ComputedChannel, ComputedMessage> {
    .init("get_messages")
  }
  var latestMessage: PostgrestToOneRelation<ComputedChannel, ComputedMessage> {
    .init("latest_message")
  }
}

@SelectionOf(ComputedUser.self)
struct ComputedUserName {
  var id: Int
  var fullName: String?
}

@SelectionOf(ComputedChannel.self)
struct ComputedChannelFeed {
  var slug: String
  @Relationship(computed: \ComputedChannel.Columns.getMessages) var messages: [ComputedMessage]
  @Relationship(computed: \ComputedChannel.Columns.latestMessage) var latest: ComputedMessage?
}

@Suite
struct ComputedMemberIntegrationTests {
  @Test
  func aWholeRowSelectLeavesComputedMembersOut() async throws {
    let capture = RequestCapture()
    _ = try await capture.client.from(ComputedUser.self).select().execute()

    #expect(capture.query == "select=*")
  }

  @Test
  func aSelectionNamesAComputedFieldLikeAColumn() {
    #expect(ComputedUserName.selectString == "id:id,full_name:full_name")
  }

  @Test
  func aComputedFieldFiltersAndOrders() async throws {
    let capture = RequestCapture()
    _ = try await capture.client
      .from(ComputedUser.self)
      .select(ComputedUserName.self)
      .where { $0.fullName.eq("Ada") || $0.fullName.isNull() }
      .order { $0.fullName.desc() }
      .execute()

    #expect(
      capture.query
        == "select=id:id,full_name:full_name&or=(full_name.eq.Ada,full_name.is.null)"
        + "&order=full_name.desc"
    )
  }

  @Test
  func aComputedRelationshipEmbedsByFunctionNameWithoutAForeignKeyHint() {
    #expect(
      ComputedChannelFeed.selectString
        == "slug:slug,messages:get_messages(*),latest:latest_message(*)"
    )
  }

  @Test
  func requiringMarksAComputedRelationshipInner() async throws {
    let capture = RequestCapture()
    _ = try await capture.client
      .from(ComputedChannel.self)
      .select(ComputedChannelFeed.self)
      .requiring(\.messages) { $0.where { $0.body.eq("hi") } }
      .execute()

    #expect(
      capture.query
        == "select=slug:slug,messages:get_messages!inner(*),latest:latest_message(*)"
        + "&messages.body=eq.hi"
    )
  }

  @Test
  func aComputedRelationshipDecodesUnderItsAlias() throws {
    let json = #"""
      {"slug":"general","messages":[{"id":1,"channel_id":3,"body":"hi"}],"latest":null}
      """#
    let row = try JSONDecoder().decode(ComputedChannelFeed.self, from: Data(json.utf8))
    #expect(row.messages.map(\.body) == ["hi"])
    #expect(row.latest == nil)
  }
}
