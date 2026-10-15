//
//  PostgrestRpcIntegrationTests.swift
//  Supabase
//
//  Created by Lukas Klingsbo on 15/10/26.
//

import Foundation
@_spi(Experimental) import PostgREST
import Testing

// The functions are in `supabase/migrations/20240101000000_initial_schema.sql`, the rows in
// `supabase/seed.sql`. Every test here is read-only.

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
}
