//
//  PostgrestRpcIntegrationTests.swift
//  Supabase
//
//  Created by Lukas Klingsbo on 15/10/26.
//

import Foundation
@_spi(Experimental) import PostgREST
import Testing

// The functions are in `supabase/migrations/20240101000000_initial_schema.sql` and
// `supabase/migrations/20261015000000_typed_functions.sql`, the rows in `supabase/seed.sql`, and
// the generated calls in `Generated.swift`. Every test here is read-only.

struct UsernameAndStatus: _PostgrestRelation {
  static let relationName = "get_username_and_status"
  static let selectString = "*"

  var username: String?
  var status: UserStatus?

  struct Columns: Sendable {
    let username = _PostgrestNullableColumn<UsernameAndStatus, String>("username")
    let status = _PostgrestNullableColumn<UsernameAndStatus, UserStatus>("status")
  }

  static let columns = Columns()
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct PostgrestRpcIntegrationTests {
  let client = PostgrestClient(
    url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
    headers: ["apikey": DotEnv.supabasePublishableKey]
  )

  @Test
  func rowsOfAReturnsTableFunctionFilterAndSort() async throws {
    let query: _PostgrestQuery<UsernameAndStatus, [UsernameAndStatus]> = try client.rpc.rows(
      "get_username_and_status", arguments: ["name_param": "supabot"])

    let rows = try await query.where { $0.status.eq(.online) }.order { $0.username.asc() }
      .execute()
      .value

    #expect(rows.map(\.username) == ["supabot"])
    #expect(rows.map(\.status) == [.online])
  }

  @Test
  func rowsAreCounted() async throws {
    let query: _PostgrestQuery<UsernameAndStatus, [UsernameAndStatus]> = try client.rpc.rows(
      "get_username_and_status", arguments: ["name_param": "supabot"])

    #expect(try await query.count(.exact) == 1)
  }

  @Test
  func aValueAMissingValueAndNoValue() async throws {
    let status: String? = try await client.rpc
      .value("get_status", arguments: ["name_param": "supabot"])
      .execute()
      .value
    #expect(status == "ONLINE")

    let missing: String? = try await client.rpc
      .value("get_status", arguments: ["name_param": "nobody"])
      .execute()
      .value
    #expect(missing == nil)

    let element: Int? = try await client.rpc
      .value("get_array_element", arguments: ["arr": [37, 420, 64], "index": 2])
      .execute()
      .value
    #expect(element == 420)

    try await client.rpc.perform("void_func").execute()
  }

  @Test
  func generatedCallsReturnRowsOfARelation() async throws {
    let messages = try await client.rpc.searchMessages(query: "hello")
      .where { $0.channelId.eq(1) }
      .execute()
      .value
    #expect(messages.map(\.id) == [1])

    let none = try await client.rpc.searchMessages(query: "hello", channelId: 2).execute().value
    #expect(none.isEmpty)
  }

  @Test
  func generatedOverloadsAreToldApartByTheirLabels() async throws {
    let byID = try await client.rpc.messagesOf(channelId: 2).execute().value
    #expect(byID.map(\.id) == [2])

    let bySlug = try await client.rpc.messagesOf(channelSlug: "public", maxCount: 1).execute()
      .value
    #expect(bySlug.map(\.id) == [1])
  }

  @Test
  func generatedCallsReturnOneRowOrNone() async throws {
    let message = try await client.rpc.messageById(messageId: 1).execute().value
    #expect(message?.username == "supabot")

    let missing = try await client.rpc.messageById(messageId: 99).execute().value
    #expect(missing == nil)
  }

  @Test
  func generatedCallsReturnTableRows() async throws {
    let counts = try await client.rpc.channelMessageCounts()
      .order { $0.channelId.asc() }
      .execute()
      .value
    #expect(counts.map(\.slug) == ["public", "random"])
    #expect(counts.map(\.messageCount) == [1, 1])

    #expect(try await client.rpc.channelMessageCounts(minMessages: 2).count(.exact) == 0)
  }

  @Test
  func generatedCallsReturnValues() async throws {
    let ids = try await client.rpc.messageIds(statuses: [.online]).execute().value
    #expect(ids == [1, 2])

    let echoed = try await client.rpc.echo(["a": 1]).execute().value
    #expect(echoed == ["a": 1])

    try await client.rpc.voidFunc().execute()
  }
}
