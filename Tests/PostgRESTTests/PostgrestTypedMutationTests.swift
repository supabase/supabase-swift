//
//  PostgrestTypedMutationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/08/26.
//

import Foundation
import Testing

@testable import PostgREST

@Suite
struct PostgrestTypedMutationTests {
  struct Todo: PostgrestWritableRelation, PostgrestKeyedRelation {
    static let relationName = "todos"
    static let schema = "public"
    static let selectString = "*"

    var id: Int
    var task: String
    var isDone: Bool
    var note: String?

    /// A hand-written conformance keeps these in step with `Columns` by hand; `@Column`
    /// generates both from one input.
    enum CodingKeys: String, CodingKey {
      case id
      case task
      case isDone = "is_done"
      case note
    }

    struct Columns: Sendable {
      let id = PostgrestColumn<Todo, Int>("id")
      let task = PostgrestColumn<Todo, String>("task")
      let isDone = PostgrestColumn<Todo, Bool>("is_done")
      let note = PostgrestNullableColumn<Todo, String>("note")
    }

    static let columns = Columns()
    static let primaryKeyColumns = ["id"]

    struct Draft: Encodable, Sendable {
      var task: String
      var isDone: Bool?

      /// Mirrors the relation's own mapping, so a batch's `columns` parameter is asserted in the
      /// database's spelling rather than in Swift's.
      enum CodingKeys: String, CodingKey {
        case task
        case isDone = "is_done"
      }
    }
  }

  /// A view: conforms to `PostgrestRelation` only, so the writes must not be offered.
  struct ActiveTodo: PostgrestRelation {
    static let relationName = "active_todos"
    static let schema = "public"
    static let selectString = "*"

    var id: Int

    struct Columns: Sendable {
      let id = PostgrestColumn<ActiveTodo, Int>("id")
    }

    static let columns = Columns()
  }

  @Test
  func insertSendsTheDraftShape() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .insert(Todo.Draft(task: "buy milk", isDone: nil)).execute()
    #expect(capture.httpMethod == "POST")
    // The hand-written `Draft` here omits the primary key, so `id` must not appear in the body.
    #expect(capture.bodyString?.contains("\"task\":\"buy milk\"") == true)
    #expect(capture.bodyString?.contains("\"id\"") == false)
  }

  @Test
  func preferHeaderIsUnambiguousWhenReturningRows() async throws {
    let capture = QueryCapture(body: #"[{"id":1,"task":"buy milk","is_done":false}]"#)
    _ = try await capture.client.from(Todo.self)
      .insert(Todo.Draft(task: "buy milk", isDone: nil)).returning().execute()
    let prefer = capture.header("Prefer") ?? ""
    #expect(prefer.contains("return=representation"))
    #expect(prefer.contains("return=minimal") == false)
  }

  @Test
  func updateScopesByFilter() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .update { $0.task = "done" }.where { $0.id.eq(1) }.execute()
    #expect(capture.query?.contains("id=eq.1") == true)
  }

  @Test
  func updateSendsAnExplicitNullForAnAssignedNil() async throws {
    // The whole point of SDK-1610: the body has to carry `null`, not drop the key.
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .update { $0.note = nil }.where { $0.id.eq(1) }.execute()
    #expect(capture.bodyString == #"{"note":null}"#)
  }

  @Test
  func updateOmitsAColumnItNeverNames() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .update { $0.task = "done" }.where { $0.id.eq(1) }.execute()
    #expect(capture.bodyString == #"{"task":"done"}"#)
  }

  @Test
  func anUpdateBuiltAheadOfTimeCanBeHandedToTheSource() async throws {
    // The payload is a value, so one layer can decide the change and another can send it.
    let update = PostgrestUpdate<Todo> { $0.note = nil }
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self).update(update).where { $0.id.eq(1) }.execute()
    #expect(capture.bodyString == #"{"note":null}"#)
  }

  @Test
  func deleteScopesByFilter() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self).delete().where { $0.id.eq(1) }.execute()
    #expect(capture.query?.contains("id=eq.1") == true)
  }

  @Test
  func returningDecodesRows() async throws {
    let capture = QueryCapture(body: #"[{"id":1,"task":"buy milk","is_done":false}]"#)
    let rows = try await capture.client.from(Todo.self)
      .insert(Todo.Draft(task: "buy milk", isDone: nil)).returning().execute().value
    #expect(rows.first?.task == "buy milk")
  }

  @Test
  func singleRowInsertSendsAnObjectAndNoColumnsParameter() async throws {
    // The `columns` parameter exists to reconcile rows that encode differently. One row cannot
    // disagree with itself, so the single-row path must stay as it was.
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .insert(Todo.Draft(task: "buy milk", isDone: nil)).execute()
    #expect(capture.bodyString?.hasPrefix("{") == true)
    #expect(capture.query?.contains("columns") != true)
  }

  @Test
  func bulkInsertSendsEveryRowInOneRequest() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .insert([Todo.Draft(task: "a", isDone: false), Todo.Draft(task: "b", isDone: false)])
      .execute()
    #expect(capture.httpMethod == "POST")
    #expect(capture.bodyString?.contains("\"task\":\"a\"") == true)
    #expect(capture.bodyString?.contains("\"task\":\"b\"") == true)
    #expect(capture.bodyString?.hasPrefix("[") == true)
  }

  @Test
  func bulkInsertNamesTheUnionOfColumnsAcrossRaggedRows() async throws {
    // A draft omits a nil optional rather than sending `null`, so these two rows encode different
    // key sets. Without the union, PostgREST reads the column list off the first row and drops
    // `is_done` from the second — the whole reason the parameter is sent.
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .insert([Todo.Draft(task: "a", isDone: nil), Todo.Draft(task: "b", isDone: true)])
      .execute()
    #expect(capture.query?.contains(#"columns="is_done","task""#) == true)
  }

  @Test
  func bulkInsertOfAnEmptyCollectionWritesNothingRatherThanFailing() async throws {
    // Decided behavior: an empty batch is a request that writes nothing, not an error. The
    // `columns` parameter has to be left off — `columns=` names one column called "", which
    // PostgREST rejects, and a no-op that 400s is not a no-op.
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self).insert([Todo.Draft]()).execute()
    #expect(capture.bodyString == "[]")
    #expect(capture.query?.contains("columns") != true)
  }

  @Test
  func bulkInsertTakesAnyCollection() async throws {
    // `some Collection` rather than `[Draft]`, so a slice reaches the wire without the caller
    // rebuilding an array.
    let rows = [Todo.Draft(task: "a"), Todo.Draft(task: "b"), Todo.Draft(task: "c")]
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self).insert(rows[1...]).execute()
    #expect(capture.bodyString?.contains("\"task\":\"a\"") == false)
    #expect(capture.bodyString?.contains("\"task\":\"c\"") == true)
  }

  @Test
  func bulkInsertCanReturnTheRows() async throws {
    let capture = QueryCapture(
      body: #"[{"id":1,"task":"a","is_done":false},{"id":2,"task":"b","is_done":false}]"#
    )
    let rows = try await capture.client.from(Todo.self)
      .insert([Todo.Draft(task: "a"), Todo.Draft(task: "b")]).returning().execute().value
    #expect(rows.map(\.task) == ["a", "b"])
  }

  @Test
  func bulkUpsertDerivesTheConflictTargetFromThePrimaryKey() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .upsert([Todo.Draft(task: "a"), Todo.Draft(task: "b")]).execute()
    #expect(capture.query?.contains("on_conflict=id") == true)
    #expect(capture.bodyString?.hasPrefix("[") == true)
  }

  @Test
  func bulkUpsertTakesAnExplicitConflictTarget() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .upsert([Todo.Draft(task: "a"), Todo.Draft(task: "b")], onConflict: \.task).execute()
    #expect(capture.query?.contains("on_conflict=task") == true)
  }

  @Test
  func bulkUpsertTakesAConflictTargetSpanningSeveralColumns() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .upsert([Todo.Draft(task: "a")], onConflict: \.id, \.task).execute()
    #expect(capture.query?.contains("on_conflict=id,task") == true)
  }

  @Test
  func bulkUpsertNamesTheUnionOfColumnsAcrossRaggedRows() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .upsert([Todo.Draft(task: "a", isDone: nil), Todo.Draft(task: "b", isDone: true)])
      .execute()
    #expect(capture.query?.contains(#"columns="is_done","task""#) == true)
  }

  @Test
  func bulkUpsertOfAnEmptyCollectionWritesNothingRatherThanFailing() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self).upsert([Todo.Draft]()).execute()
    #expect(capture.bodyString == "[]")
    #expect(capture.query?.contains("columns") != true)
  }
}
