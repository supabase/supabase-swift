//
//  PostgrestFunctionIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 07/10/26.
//

import Foundation
import PostgrestMacros
import Testing

// File scope: `@Function` and `@Table` attach extensions, which cannot be nested in a type. The
// functions are in `supabase/migrations/20240101000000_initial_schema.sql`; the rows are the seed
// users. Every test here is read-only.

@Function("get_status")
struct GetStatus {
  typealias Result = String
  var nameParam: String
}

@Function("void_func")
struct VoidFunc {}

@Table("users", readOnly: true)
struct FunctionUser {
  var username: String?
  var status: String
}

@Function("get_username_and_status")
struct GetUsernameAndStatus {
  typealias Result = [FunctionUser]
  var nameParam: String
}

/// The typed `rpc(_:)` against a live PostgREST: a scalar function, a void one, and a set-returning
/// one whose rows take a filter.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct PostgrestFunctionIntegrationTests {
  let client = PostgrestClient(
    url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
    headers: ["apikey": DotEnv.supabasePublishableKey]
  )

  @Test
  func aScalarFunctionReturnsItsValue() async throws {
    let status = try await client.rpc(GetStatus(nameParam: "supabot")).execute().value
    #expect(status == "ONLINE")
  }

  @Test
  func readOnlySendsTheArgumentsInTheQueryString() async throws {
    let status = try await client.rpc(GetStatus(nameParam: "kiwicopple")).readOnly().execute().value
    #expect(status == "OFFLINE")
  }

  @Test
  func aVoidFunctionExecutes() async throws {
    try await client.rpc(VoidFunc()).execute()
  }

  @Test
  func theRowsOfASetReturningFunctionTakeAFilter() async throws {
    let matching = try await client.rpc(GetUsernameAndStatus(nameParam: "supabot"))
      .where { $0.status.eq("ONLINE") }
      .execute().value
    #expect(matching.map(\.username) == ["supabot"])

    let filteredOut = try await client.rpc(GetUsernameAndStatus(nameParam: "supabot"))
      .readOnly()
      .where { $0.status.eq("OFFLINE") }
      .execute().value
    #expect(filteredOut.isEmpty)
  }
}
