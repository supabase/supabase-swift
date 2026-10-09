//
//  TypedUntypedParityTests.swift
//  PostgREST
//
//  Created by Guilherme Souza on 07/10/26.
//

import CustomDump
import Foundation
import Testing

@_spi(Experimental) @testable import PostgREST

/// The typed API and the untyped string builders share one request core, so one operation spelled
/// both ways has to put the same bytes on the wire. Each test builds a request through
/// `from(Todo.self)` and through `from("todos")` and compares everything the transport sees.
///
/// Two rows are missing on purpose:
///
/// - `rpc` has no typed spelling yet (SDK-1577).
/// - `maybeSingle()` differs by design: the typed one asks for the array and enforces the row
///   count client-side (SDK-1635), the untyped one asks for the object media type.
@Suite
struct TypedUntypedParityTests {
  struct Todo: _PostgrestWritableRelation, _PostgrestKeyedRelation {
    static let relationName = "todos"
    static let selectString = "*"

    var id: Int
    var task: String
    var isDone: Bool
    var note: String?
    var tags: [String]

    enum CodingKeys: String, CodingKey {
      case id
      case task
      case isDone = "is_done"
      case note
      case tags
    }

    struct Columns: Sendable {
      let id = _PostgrestColumn<Todo, Int>("id")
      let task = _PostgrestColumn<Todo, String>("task")
      let isDone = _PostgrestColumn<Todo, Bool>("is_done")
      let note = _PostgrestNullableColumn<Todo, String>("note")
      let tags = _PostgrestColumn<Todo, [String]>("tags")
    }

    static let columns = Columns()
    static let primaryKeyColumns = ["id"]

    struct Draft: Encodable, Sendable {
      var task: String
      var isDone: Bool?

      enum CodingKeys: String, CodingKey {
        case task
        case isDone = "is_done"
      }
    }
  }

  /// What the transport sees, which is all a parity check is allowed to care about.
  struct Wire: Equatable {
    var method: String?
    var path: String?
    var query: String?
    var headers: [String: String]
    var body: String?

    init(_ capture: QueryCapture) {
      method = capture.httpMethod
      path = capture.path
      query = capture.query
      headers = capture.headers
      body = capture.bodyString
    }
  }

  private func expectParity(
    body: String = "[]",
    responseHeaders: [String: String] = [:],
    typed: (PostgrestClient) async throws -> Void,
    untyped: (PostgrestClient) async throws -> Void,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) async throws {
    let typedCapture = QueryCapture(body: body, responseHeaders: responseHeaders)
    let untypedCapture = QueryCapture(body: body, responseHeaders: responseHeaders)
    try await typed(typedCapture.client)
    try await untyped(untypedCapture.client)
    expectNoDifference(
      Wire(typedCapture), Wire(untypedCapture),
      fileID: fileID, filePath: filePath, line: line, column: column)
  }

  // MARK: - select

  @Test
  func selectWholeRow() async throws {
    try await expectParity {
      _ = try await $0.from(Todo.self).select().execute()
    } untyped: {
      _ = try await $0.from("todos").select().execute()
    }
  }

  @Test
  func selectUnderAnotherSchema() async throws {
    try await expectParity {
      _ = try await $0.schema("tenant").from(Todo.self).select().execute()
    } untyped: {
      _ = try await $0.schema("tenant").from("todos").select().execute()
    }
  }

  // MARK: - filters

  @Test
  func comparisons() async throws {
    try await expectParity {
      _ = try await $0.from(Todo.self).select()
        .where {
          $0.id.gt(1) && $0.id.lte(9) && $0.task.neq("x") && $0.isDone.eq(false)
            && $0.id.isDistinct(3)
        }
        .execute()
    } untyped: {
      _ = try await $0.from("todos").select()
        .gt("id", value: 1).lte("id", value: 9).neq("task", value: "x")
        .eq("is_done", value: false).isDistinct("id", value: 3)
        .execute()
    }
  }

  /// Spec §9.5: a top-level scalar operand runs to the end of the parameter, so neither path
  /// quotes it. Quoting would make `eq."a,b"` match nothing.
  @Test
  func scalarOperandsWithStructuralCharactersStayUnquoted() async throws {
    try await expectParity {
      _ = try await $0.from(Todo.self).select()
        .where { $0.task.eq("a,b") && $0.task.like("a(b)%") }
        .execute()
    } untyped: {
      _ = try await $0.from("todos").select()
        .eq("task", value: "a,b").like("task", pattern: "a(b)%")
        .execute()
    }
  }

  @Test
  func inListQuotesEveryMemberThatNeedsIt() async throws {
    try await expectParity {
      _ = try await $0.from(Todo.self).select()
        .where { $0.task.in(["a,b", "c"]) && !$0.id.in([1, 2]) }
        .execute()
    } untyped: {
      _ = try await $0.from("todos").select()
        .in("task", values: ["a,b", "c"]).notIn("id", values: [1, 2])
        .execute()
    }
  }

  @Test
  func isChecks() async throws {
    try await expectParity {
      _ = try await $0.from(Todo.self).select()
        .where { $0.note.isNull() && $0.isDone.isTrue() && !$0.isDone.isFalse() }
        .execute()
    } untyped: {
      _ = try await $0.from("todos").select()
        .is("note", value: nil).is("is_done", value: true)
        .not("is_done", operator: .is, value: false)
        .execute()
    }
  }

  @Test
  func negatedComparison() async throws {
    try await expectParity {
      _ = try await $0.from(Todo.self).select().where { !$0.id.eq(1) }.execute()
    } untyped: {
      _ = try await $0.from("todos").select().not("id", operator: .eq, value: 1).execute()
    }
  }

  /// The untyped `or` takes PostgREST grammar as written, so its caller quotes by hand what the
  /// typed renderer quotes for them.
  @Test
  func orGroup() async throws {
    try await expectParity {
      _ = try await $0.from(Todo.self).select()
        .where { $0.id.eq(1) || $0.task.eq("a,b") || ($0.isDone.eq(true) && $0.id.gt(5)) }
        .execute()
    } untyped: {
      _ = try await $0.from("todos").select()
        .or(#"id.eq.1,task.eq."a,b",and(is_done.eq.true,id.gt.5)"#)
        .execute()
    }
  }

  @Test
  func patterns() async throws {
    try await expectParity {
      _ = try await $0.from(Todo.self).select()
        .where {
          $0.task.ilike("A%") && $0.task.likeAnyOf(["a%", "b%"])
            && $0.task.ilikeAllOf(["%a", "%b"])
            && $0.task.regexMatch("^a") && $0.task.regexIMatch("^B")
        }
        .execute()
    } untyped: {
      _ = try await $0.from("todos").select()
        .ilike("task", pattern: "A%").likeAnyOf("task", patterns: ["a%", "b%"])
        .iLikeAllOf("task", patterns: ["%a", "%b"])
        .match("task", pattern: "^a").imatch("task", pattern: "^B")
        .execute()
    }
  }

  @Test
  func arrayOperators() async throws {
    try await expectParity {
      _ = try await $0.from(Todo.self).select()
        .where {
          $0.tags.contains(["a", "b c"]) && $0.tags.containedBy(["a", "b c", "d"])
            && $0.tags.overlaps(["a"])
        }
        .execute()
    } untyped: {
      _ = try await $0.from("todos").select()
        .contains("tags", value: ["a", "b c"]).containedBy("tags", value: ["a", "b c", "d"])
        .overlaps("tags", value: ["a"])
        .execute()
    }
  }

  @Test
  func textSearch() async throws {
    try await expectParity {
      _ = try await $0.from(Todo.self).select()
        .where {
          $0.task.textSearch("fat & cat") && $0.task.textSearch("fat cat", config: "english")
            && $0.task.textSearch("fat cat", type: .websearch)
        }
        .execute()
    } untyped: {
      _ = try await $0.from("todos").select()
        .textSearch("task", query: "fat & cat")
        .fts("task", query: "fat cat", config: "english")
        .textSearch("task", query: "fat cat", type: .websearch)
        .execute()
    }
  }

  @Test
  func rawEscapeHatch() async throws {
    try await expectParity {
      _ = try await $0.from(Todo.self).select()
        .where { $0.task.raw("someop.value") && .raw("cost::text", "eq.10") }
        .execute()
    } untyped: {
      _ = try await $0.from("todos").select()
        .filter("task", operator: "someop", value: "value")
        .filter("cost::text", operator: "eq", value: "10")
        .execute()
    }
  }

  // MARK: - modifiers

  @Test
  func orderLimitAndRange() async throws {
    try await expectParity {
      _ = try await $0.from(Todo.self).select()
        .order { $0.id.desc() }.order { $0.task.asc() }.range(10...19)
        .execute()
    } untyped: {
      _ = try await $0.from("todos").select()
        .order("id", ascending: false).order("task").range(from: 10, to: 19)
        .execute()
    }
    try await expectParity {
      _ = try await $0.from(Todo.self).select().limit(5).execute()
    } untyped: {
      _ = try await $0.from("todos").select().limit(5).execute()
    }
  }

  @Test
  func single() async throws {
    let row = #"{"id":1,"task":"a","is_done":false,"note":null,"tags":[]}"#
    try await expectParity(body: row) {
      _ = try await $0.from(Todo.self).select().where { $0.id.eq(1) }.single().execute()
    } untyped: {
      let _: PostgrestResponse<Todo> = try await $0.from("todos").select()
        .eq("id", value: 1).single().execute()
    }
  }

  @Test
  func stripNulls() async throws {
    try await expectParity {
      _ = try await $0.from(Todo.self).select().stripNulls().execute()
    } untyped: {
      _ = try await $0.from("todos").select().stripNulls().execute()
    }
    let row = #"{"id":1,"task":"a","is_done":false,"tags":[]}"#
    try await expectParity(body: row) {
      _ = try await $0.from(Todo.self).select().stripNulls().single().execute()
    } untyped: {
      let _: PostgrestResponse<Todo> = try await $0.from("todos").select()
        .stripNulls().single().execute()
    }
  }

  @Test
  func csvAndGeoJSON() async throws {
    try await expectParity(body: "id,task\n1,a\n") {
      _ = try await $0.from(Todo.self).select().csv().execute()
    } untyped: {
      _ = try await $0.from("todos").select().csv().execute()
    }
    try await expectParity(body: "{}") {
      _ = try await $0.from(Todo.self).select().geojson().execute()
    } untyped: {
      _ = try await $0.from("todos").select().geojson().execute()
    }
  }

  @Test
  func explain() async throws {
    try await expectParity(body: "plan") {
      _ = try await $0.from(Todo.self).select().explain(analyze: true, format: .json).execute()
    } untyped: {
      _ = try await $0.from("todos").select().explain(analyze: true, format: .json).execute()
    }
  }

  @Test
  func countOnly() async throws {
    try await expectParity(body: "", responseHeaders: ["Content-Range": "0-0/5"]) {
      _ = try await $0.from(Todo.self).select().count(.exact)
    } untyped: {
      _ = try await $0.from("todos").select(head: true, count: .exact).execute()
    }
  }

  @Test
  func rowsWithCount() async throws {
    try await expectParity(responseHeaders: ["Content-Range": "0-0/5"]) {
      _ = try await $0.from(Todo.self).select().execute(count: .estimated)
    } untyped: {
      _ = try await $0.from("todos").select(count: .estimated).execute()
    }
  }

  // MARK: - writes

  @Test
  func insertOneRow() async throws {
    let draft = Todo.Draft(task: "a", isDone: nil)
    try await expectParity {
      _ = try await $0.from(Todo.self).insert(draft).execute()
    } untyped: {
      _ = try await $0.from("todos").insert(draft, returning: .minimal).execute()
    }
  }

  @Test
  func insertABatch() async throws {
    let drafts = [Todo.Draft(task: "a", isDone: nil), Todo.Draft(task: "b", isDone: true)]
    try await expectParity {
      _ = try await $0.from(Todo.self).insert(drafts).execute()
    } untyped: {
      _ = try await $0.from("todos").insert(drafts, returning: .minimal).execute()
    }
  }

  @Test
  func insertReturningRows() async throws {
    let draft = Todo.Draft(task: "a", isDone: nil)
    try await expectParity {
      _ = try await $0.from(Todo.self).insert(draft).returning().execute()
    } untyped: {
      _ = try await $0.from("todos").insert(draft, returning: .representation).execute()
    }
  }

  @Test
  func upsert() async throws {
    let draft = Todo.Draft(task: "a", isDone: nil)
    try await expectParity {
      _ = try await $0.from(Todo.self).upsert(draft).execute()
    } untyped: {
      _ = try await $0.from("todos").upsert(draft, onConflict: "id", returning: .minimal).execute()
    }
    try await expectParity {
      _ = try await $0.from(Todo.self)
        .upsert(draft, onConflict: \.task, resolution: .ignoreDuplicates).execute()
    } untyped: {
      _ = try await $0.from("todos")
        .upsert(draft, onConflict: "task", returning: .minimal, ignoreDuplicates: true).execute()
    }
  }

  @Test
  func update() async throws {
    try await expectParity {
      _ = try await $0.from(Todo.self).update { $0.task = "b" }.where { $0.id.eq(1) }.execute()
    } untyped: {
      _ = try await $0.from("todos").update(["task": "b"], returning: .minimal)
        .eq("id", value: 1).execute()
    }
    try await expectParity {
      _ = try await $0.from(Todo.self).update { $0.task = "b" }.where { $0.id.eq(1) }
        .returning().execute()
    } untyped: {
      _ = try await $0.from("todos").update(["task": "b"], returning: .representation)
        .eq("id", value: 1).execute()
    }
  }

  @Test
  func delete() async throws {
    try await expectParity {
      _ = try await $0.from(Todo.self).delete().where { $0.id.eq(1) }.execute()
    } untyped: {
      _ = try await $0.from("todos").delete(returning: .minimal).eq("id", value: 1).execute()
    }
  }
}
