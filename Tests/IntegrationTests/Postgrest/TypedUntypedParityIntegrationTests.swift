//
//  TypedUntypedParityIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 07/10/26.
//

import CustomDump
import Foundation
@_spi(Experimental) import PostgrestMacros
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct TypedUntypedParityIntegrationTests {
  let client = PostgrestClient(
    url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
    headers: ["apikey": DotEnv.supabasePublishableKey]
  )

  private func expectSameRows(
    typed: _PostgrestQuery<Users, [Users]>,
    untyped: PostgrestFilterBuilder,
    count: Int,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async throws {
    let typedRows = try await typed.order { $0.username.asc() }.execute().value
    let untypedRows: [Users] = try await untyped.order("username").execute().value
    #expect(
      String(customDumping: typedRows) == String(customDumping: untypedRows),
      sourceLocation: sourceLocation
    )
    #expect(typedRows.count >= count, sourceLocation: sourceLocation)
  }

  @Test
  func isNullMatchesTheSeedRowsWithoutAnEmail() async throws {
    try await expectSameRows(
      typed: client.from(Users.self).select().where { $0.email.isNull() },
      untyped: client.from("users").select().is("email", value: nil),
      count: 4)
  }

  @Test
  func negatedComparison() async throws {
    try await expectSameRows(
      typed: client.from(Users.self).select().where { !$0.status.eq(.offline) },
      untyped: client.from("users").select().not("status", operator: .eq, value: "OFFLINE"),
      count: 3)
  }

  @Test
  func scalarOperandWithQuotesAndSpaces() async throws {
    try await expectSameRows(
      typed: client.from(Users.self).select().where { $0.catchphrase.eq("'cat' 'fat'") },
      untyped: client.from("users").select().eq("catchphrase", value: "'cat' 'fat'"),
      count: 1)
  }

  @Test
  func inListQuotesItsMembers() async throws {
    let phrases = ["'cat' 'fat'", "'bat' 'cat'"]
    try await expectSameRows(
      typed: client.from(Users.self).select().where { $0.catchphrase.in(phrases) },
      untyped: client.from("users").select().in("catchphrase", values: phrases),
      count: 2)
  }

  @Test
  func orGroupWithAQuotedOperand() async throws {
    try await expectSameRows(
      typed: client.from(Users.self).select()
        .where { $0.catchphrase.eq("'cat' 'fat'") || $0.username.eq("awailas") },
      untyped: client.from("users").select()
        .or(#"catchphrase.eq."'cat' 'fat'",username.eq.awailas"#),
      count: 2)
  }

  @Test
  func textSearch() async throws {
    try await expectSameRows(
      typed: client.from(Users.self).select()
        .where { $0.catchphrase.textSearch("'fat' & 'rat'", config: "english") },
      untyped: client.from("users").select()
        .textSearch("catchphrase", query: "'fat' & 'rat'", config: "english"),
      count: 1)
  }

  @Test
  func rawEscapeHatch() async throws {
    try await expectSameRows(
      typed: client.from(Users.self).select().where { $0.username.raw("like.*a*") },
      untyped: client.from("users").select().filter("username", operator: "like", value: "*a*"),
      count: 3)
  }
}
