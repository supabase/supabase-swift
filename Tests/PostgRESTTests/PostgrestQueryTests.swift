//
//  PostgrestQueryTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 31/08/26.
//

import Foundation
import Testing

@_spi(Experimental) @testable import PostgREST

@Suite
struct PostgrestQueryTests {
  struct Todo: _PostgrestWritableRelation {
    static let relationName = "todos"
    static let selectString = "*"

    var id: Int
    var task: String

    struct Columns: Sendable {
      let id = _PostgrestColumn<Todo, Int>("id")
      let isDone = _PostgrestColumn<Todo, Bool>("is_done")
    }

    static let columns = Columns()

    struct Draft: Encodable, Sendable {
      var task: String
    }
  }

  @Test
  func countAsksForTheTotalWithoutTransferringRows() async throws {
    let capture = try QueryCapture(responseHeaders: ["Content-Range": "*/42"])
    let total = try await capture.client.from(Todo.self).select().count(.exact)
    #expect(total == 42)
    #expect(capture.httpMethod == "HEAD")
    #expect(capture.header("Prefer")?.contains("count=exact") == true)
  }

  @Test
  func countRespectsFilters() async throws {
    let capture = try QueryCapture(responseHeaders: ["Content-Range": "*/3"])
    _ = try await capture.client.from(Todo.self).select()
      .where { $0.isDone.eq(false) }.count(.planned)
    #expect(capture.query?.contains("is_done=eq.false") == true)
    #expect(capture.header("Prefer")?.contains("count=planned") == true)
  }

  @Test
  func countThrowsWhenTheServerSendsNoTotal() async throws {
    let capture = try QueryCapture()
    await #expect(throws: PostgrestError.self) {
      _ = try await capture.client.from(Todo.self).select().count(.exact)
    }
  }

  @Test
  func executeWithACountReturnsBothRowsAndTotal() async throws {
    let capture = try QueryCapture(
      body: #"[{"id":1,"task":"buy milk"}]"#,
      responseHeaders: ["Content-Range": "0-0/42"]
    )
    let response = try await capture.client.from(Todo.self).select().limit(1)
      .execute(count: .exact)
    #expect(response.value.count == 1)
    #expect(response.count == 42)
    #expect(capture.httpMethod == "GET")
    #expect(capture.header("Prefer")?.contains("count=exact") == true)
  }

  @Test
  func executeWithoutACountAsksForNoPreference() async throws {
    let capture = try QueryCapture()
    _ = try await capture.client.from(Todo.self).select().execute()
    #expect(capture.header("Prefer") == nil)
  }

  @Test
  func aMutationCountsAffectedRowsWithoutReturningThem() async throws {
    let capture = try QueryCapture(responseHeaders: ["Content-Range": "*/7"])
    let response = try await capture.client.from(Todo.self).delete()
      .where { $0.isDone.eq(true) }.execute(count: .exact)
    #expect(response.count == 7)
    let prefer = capture.header("Prefer") ?? ""
    #expect(prefer.contains("count=exact"))
    #expect(prefer.contains("return=") == false)
  }

  @Test
  func aMutationCountComposesWithReturning() async throws {
    let capture = try QueryCapture(
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

  @Test
  func whereAfterOrderStillFilters() async throws {
    let capture = try QueryCapture()
    _ = try await capture.client.from(Todo.self).select()
      .order { $0.id.asc() }.limit(5).where { $0.isDone.eq(false) }.execute()
    #expect(capture.query?.contains("order=id.asc") == true)
    #expect(capture.query?.contains("limit=5") == true)
    #expect(capture.query?.contains("is_done=eq.false") == true)
  }

  @Test
  func rangeSendsOffsetAndInclusiveLimit() async throws {
    let capture = try QueryCapture()
    _ = try await capture.client.from(Todo.self).select().range(10...19).execute()
    #expect(capture.query?.contains("offset=10") == true)
    #expect(capture.query?.contains("limit=10") == true)
  }

  @Test
  func singleDecodesOneRow() async throws {
    let capture = try QueryCapture(body: #"{"id":1,"task":"buy milk"}"#)
    let todo: Todo = try await capture.client.from(Todo.self).select().single().execute().value
    #expect(todo.task == "buy milk")
    #expect(capture.header("Accept") == "application/vnd.pgrst.object+json")
  }

  @Test
  func maybeSingleDecodesOneRow() async throws {
    let capture = try QueryCapture(body: #"[{"id":1,"task":"buy milk"}]"#)
    let todo: Todo? = try await capture.client.from(Todo.self).select().maybeSingle().execute()
      .value
    #expect(todo?.task == "buy milk")
    #expect(capture.header("Accept") == "application/json")
  }

  @Test
  func maybeSingleTurnsNoRowsIntoNil() async throws {
    let capture = try QueryCapture(body: "[]")
    let todo = try await capture.client.from(Todo.self).select().maybeSingle().execute().value
    #expect(todo == nil)
  }

  @Test
  func maybeSingleThrowsPGRST116ForMoreThanOneRow() async throws {
    let capture = try QueryCapture(body: #"[{"id":1,"task":"a"},{"id":2,"task":"b"}]"#)
    let error = await #expect(throws: PostgrestError.self) {
      _ = try await capture.client.from(Todo.self).select().maybeSingle().execute()
    }
    #expect(error?.kind == .server)
    #expect(error?.code == "PGRST116")
    #expect(error?.response?.status == .notAcceptable)
    #expect(error?.serverError?.details == "The result contains 2 rows")
  }

  @Test(arguments: [
    #"[]"#,
    #"[{"id":1,"task":"buy milk"}]"#,
    #"[{"id":1,"task":"a"},{"id":2,"task":"b"}]"#,
  ])
  func maybeSingleBehavesTheSameOnTheTypedAndUntypedPaths(body: String) async throws {
    let capture = try QueryCapture(body: body)
    let typed = await result {
      try await capture.client.from(Todo.self).select().maybeSingle().execute()
    }
    let typedAccept = capture.header("Accept")
    let untyped = await result {
      try await capture.client.from("todos").select().maybeSingle().execute()
        as PostgrestResponse<Todo?>
    }
    #expect(capture.header("Accept") == typedAccept)

    switch (typed, untyped) {
    case (.success(let typed), .success(let untyped)):
      #expect(typed.value?.task == untyped.value?.task)
      #expect(typed.status == untyped.status)
      #expect(typed.body == untyped.body)
    case (.failure(let typed as PostgrestError), .failure(let untyped as PostgrestError)):
      #expect(typed.kind == untyped.kind)
      #expect(typed.code == untyped.code)
      #expect(typed.serverError == untyped.serverError)
      #expect(typed.response?.status == untyped.response?.status)
    default:
      Issue.record("The paths disagree: typed \(typed), untyped \(untyped)")
    }
  }

  private func result<T>(_ body: () async throws -> T) async -> Result<T, any Error> {
    do { return .success(try await body()) } catch { return .failure(error) }
  }

  @Test
  func singleThrowsForNoRows() async throws {
    let capture = try QueryCapture(
      body: #"""
        {"code":"PGRST116","message":"Cannot coerce the result to a single JSON object",\#
        "details":"The result contains 0 rows","hint":null}
        """#,
      status: .notAcceptable
    )
    await #expect(throws: PostgrestError.self) {
      _ = try await capture.client.from(Todo.self).select().single().execute()
    }
  }

  @Test
  func stripNullsAsksForTheStrippedArrayMediaType() async throws {
    let capture = try QueryCapture()
    _ = try await capture.client.from(Todo.self).select().stripNulls().execute()
    #expect(capture.header("Accept") == "application/vnd.pgrst.array+json;nulls=stripped")
  }

  @Test
  func stripNullsBeforeSingleAsksForTheStrippedObjectMediaType() async throws {
    let capture = try QueryCapture(body: #"{"id":1,"task":"buy milk"}"#)
    _ = try await capture.client.from(Todo.self).select().stripNulls().single().execute()
    #expect(capture.header("Accept") == "application/vnd.pgrst.object+json;nulls=stripped")
  }

  @Test
  func whereWorksAfterReturning() async throws {
    let capture = try QueryCapture(body: #"{"id":1,"task":"buy milk"}"#)
    let todo = try await capture.client.from(Todo.self).delete().all().returning()
      .where { $0.id.eq(1) }.single().execute().value
    #expect(todo.id == 1)
    #expect(capture.httpMethod == "DELETE")
    #expect(capture.query?.contains("id=eq.1") == true)
  }
}
