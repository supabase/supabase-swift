//
//  PostgrestNilFilterValueTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 19/08/26.
//

import Testing

@testable import PostgREST

/// `NULL` is not a comparable value in SQL: `column = NULL` is never true, and PostgREST makes that
/// worse than a no-op. Spec §9.3 measured it against a live server — on an `integer` column
/// `column=eq.null` is an HTTP 400, and on a `text` column it returns **HTTP 200 with the row whose
/// value is the literal string** `'null'`. A silently wrong row, not an empty result.
///
/// So the SDK does not translate a `nil` operand into `is.null`, and does not send it either. It
/// refuses to compile: `Optional` conforms to ``PostgrestArrayElement`` but not to
/// ``PostgrestFilterValue``, so there is nothing to pass to `eq`.
///
/// Swift Testing cannot assert that code fails to compile, so the negative cases are recorded here
/// as commented call sites and verified by hand. Each one is `error: argument type 'String?' does
/// not conform to expected type 'PostgrestFilterValue'`.
///
/// ```swift
/// let email: String? = nil
/// client.from("users").select().eq("email", value: email)   // does not compile
/// client.from("users").select().eq("email", value: nil)     // does not compile
/// client.from("users").select().neq("email", value: email)  // does not compile
/// client.from("users").select().gt("age", value: Int?.none) // does not compile
/// client.from("users").select().in("id", values: [1, nil])  // does not compile
/// ```
@Suite
struct PostgrestNilFilterValueTests {
  /// The supported way to test for `NULL`, and the reason `eq` does not need to guess.
  @Test
  func isNullSendsIsNull() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from("users").select().is("email", value: nil).execute()
    #expect(capture.query?.contains("email=is.NULL") == true)
  }

  /// The counterpart, via `not`.
  @Test
  func notIsNullSendsNotIsNull() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from("users").select()
      .not("email", operator: .is, value: "null").execute()
    #expect(capture.query?.contains("email=not.is.null") == true)
  }

  /// A non-optional value is unaffected — the point is to reject `nil`, not to narrow the API.
  @Test
  func presentValueStillUsesEq() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from("users").select().eq("email", value: "a@b.co").execute()
    #expect(capture.query?.contains("email=eq.a@b.co") == true)
  }

  /// A real Postgres array column may legitimately contain `NULL`, which is why `Optional` keeps
  /// its ``PostgrestArrayElement`` conformance.
  @Test
  func arrayColumnStillAcceptsNullMembers() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from("users").select()
      .contains("tags", value: [Optional("a"), nil]).execute()
    #expect(capture.query?.contains("tags=cs.{a,NULL}") == true)
  }
}
