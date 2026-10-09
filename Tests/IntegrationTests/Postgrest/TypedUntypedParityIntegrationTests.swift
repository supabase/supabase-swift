//
//  TypedUntypedParityIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 07/10/26.
//

import Foundation
import PostgrestMacros
import Testing

// `Users` is in `Generated.swift`. The rows are the four seed users in `supabase/seed.sql`; every
// test here is read-only.

/// The server-side half of `TypedUntypedParityTests`: the same filter spelled through
/// `from(Users.self)` and through `from("users")` has to return the same rows from a live
/// PostgREST, not only build the same query string. The cases are the ones where the two paths
/// used to format the operand differently, or where PostgREST's grammar is strict.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct TypedUntypedParityIntegrationTests {
  let client = PostgrestClient(
    url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
    headers: ["apikey": DotEnv.supabasePublishableKey]
  )

  private func expectSameRows(
    typed: PostgrestQuery<Users, [Users]>,
    untyped: PostgrestFilterBuilder,
    count: Int,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async throws {
    let typedRows = try await typed.order { $0.username.asc() }.execute().value
    let untypedRows: [Users] = try await untyped.order("username").execute().value
    // `Users` is generated without `Equatable`; both decode the same columns, so the keys suffice.
    #expect(typedRows.map(\.id) == untypedRows.map(\.id), sourceLocation: sourceLocation)
    // At least: other suites in the same run insert users of their own and delete them in their
    // `init()`, so an exact count would depend on suite order.
    #expect(typedRows.count >= count, sourceLocation: sourceLocation)
  }

  /// `is(_:value: nil)` sends `is.null` now, where it sent `is.NULL`; the server reads both.
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

  /// A scalar operand with spaces and quotes stays unquoted at top level on both paths (spec
  /// §9.5): quoting it would match nothing.
  @Test
  func scalarOperandWithQuotesAndSpaces() async throws {
    try await expectSameRows(
      typed: client.from(Users.self).select().where { $0.catchphrase.eq("'cat' 'fat'") },
      untyped: client.from("users").select().eq("catchphrase", value: "'cat' 'fat'"),
      count: 1)
  }

  /// Inside `in.(…)` the same operand must be quoted, on both paths.
  @Test
  func inListQuotesItsMembers() async throws {
    let phrases = ["'cat' 'fat'", "'bat' 'cat'"]
    try await expectSameRows(
      typed: client.from(Users.self).select().where { $0.catchphrase.in(phrases) },
      untyped: client.from("users").select().in("catchphrase", values: phrases),
      count: 2)
  }

  /// Inside `or=(…)` the typed renderer quotes the operand; the untyped caller writes the
  /// grammar by hand, quotes included.
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
