//
//  PostgrestTypedQueryTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 31/08/26.
//

import Foundation
import Testing

@testable import PostgREST

@Suite
struct PostgrestTypedQueryTests {
  struct Todo: PostgrestWritableRelation {
    static let relationName = "todos"
    static let schema = "public"
    static let selectString = "*"

    var id: Int
    var task: String

    struct Columns: Sendable {
      let id = PostgrestColumn<Todo, Int>("id")
      let isDone = PostgrestColumn<Todo, Bool>("is_done")
    }

    static let columns = Columns()

    struct Draft: Encodable, Sendable {
      var task: String
    }
  }

  @Test
  func countAsksForTheTotalWithoutTransferringRows() async throws {
    let capture = QueryCapture(responseHeaders: ["Content-Range": "*/42"])
    let total = try await capture.client.from(Todo.self).select().count(.exact)
    #expect(total == 42)
    // `head: true` is the whole point — the body is never sent, so the count costs no rows.
    #expect(capture.httpMethod == "HEAD")
    #expect(capture.header("Prefer")?.contains("count=exact") == true)
  }

  @Test
  func countRespectsFilters() async throws {
    let capture = QueryCapture(responseHeaders: ["Content-Range": "*/3"])
    _ = try await capture.client.from(Todo.self).select()
      .where { $0.isDone.eq(false) }.count(.planned)
    #expect(capture.query?.contains("is_done=eq.false") == true)
    #expect(capture.header("Prefer")?.contains("count=planned") == true)
  }

  @Test
  func countThrowsWhenTheServerSendsNoTotal() async throws {
    // No `Content-Range`, so there is no number to return and `Int` cannot be honoured.
    let capture = QueryCapture()
    await #expect(throws: PostgrestError.self) {
      _ = try await capture.client.from(Todo.self).select().count(.exact)
    }
  }

  @Test
  func executeWithACountReturnsBothRowsAndTotal() async throws {
    let capture = QueryCapture(
      body: #"[{"id":1,"task":"buy milk"}]"#,
      responseHeaders: ["Content-Range": "0-0/42"]
    )
    let response = try await capture.client.from(Todo.self).select().limit(1)
      .execute(count: .exact)
    #expect(response.value.count == 1)
    #expect(response.count == 42)
    // Still a GET: this is the page *and* the total from one round trip.
    #expect(capture.httpMethod == "GET")
    #expect(capture.header("Prefer")?.contains("count=exact") == true)
  }

  @Test
  func executeWithoutACountAsksForNoPreference() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self).select().execute()
    #expect(capture.header("Prefer") == nil)
  }

  @Test
  func aMutationCountsAffectedRowsWithoutReturningThem() async throws {
    let capture = QueryCapture(responseHeaders: ["Content-Range": "*/7"])
    let response = try await capture.client.from(Todo.self).delete()
      .where { $0.isDone.eq(true) }.execute(count: .exact)
    #expect(response.count == 7)
    let prefer = capture.header("Prefer") ?? ""
    #expect(prefer.contains("count=exact"))
    #expect(prefer.contains("return=minimal"))
  }

  @Test
  func aMutationCountComposesWithReturning() async throws {
    // The count preference is set at send time, after `returning()` has written the header, and
    // `appendOrUpdate` replaces only the `return=` component. So the two do not clobber.
    let capture = QueryCapture(
      body: #"[{"id":1,"task":"buy milk"}]"#,
      responseHeaders: ["Content-Range": "0-0/1"]
    )
    let response = try await capture.client.from(Todo.self)
      .insert(Todo.Draft(task: "buy milk")).returning().execute(count: .exact)
    #expect(response.count == 1)
    let prefer = capture.header("Prefer") ?? ""
    #expect(prefer.contains("count=exact"))
    #expect(prefer.contains("return=representation"))
    #expect(prefer.contains("return=minimal") == false)
  }
}
