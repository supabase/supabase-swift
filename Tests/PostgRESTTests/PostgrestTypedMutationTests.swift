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
  struct Todo: PostgrestWritableRelation {
    static let relationName = "todos"
    static let schema = "public"
    static let selectString = "*"

    var id: Int
    var task: String
    var isDone: Bool
    var note: String?

    /// A hand-written conformance has to keep these in step with `columnName(for:)` itself. The
    /// `@Column` macro generates both from one input so they cannot drift.
    enum CodingKeys: String, CodingKey {
      case id
      case task
      case isDone = "is_done"
      case note
    }

    static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
      switch keyPath {
      case \Self.id: "id"
      case \Self.task: "task"
      case \Self.isDone: "is_done"
      case \Self.note: "note"
      default: fatalError("unmapped key path")
      }
    }

    struct Draft: Encodable, Sendable {
      var task: String
      var isDone: Bool?
    }
  }

  /// A view: conforms to `PostgrestRelation` only, so the writes must not be offered.
  struct ActiveTodo: PostgrestRelation {
    static let relationName = "active_todos"
    static let schema = "public"
    static let selectString = "*"

    var id: Int

    static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
      switch keyPath {
      case \Self.id: "id"
      default: fatalError("unmapped key path")
      }
    }
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
  func updateScopesByKeyPath() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .update { $0.task = "done" }.eq(\.id, 1).execute()
    #expect(capture.query?.contains("id=eq.1") == true)
  }

  @Test
  func updateSendsAnExplicitNullForAnAssignedNil() async throws {
    // The whole point of SDK-1610: the body has to carry `null`, not drop the key.
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .update { $0.note = nil }.eq(\.id, 1).execute()
    #expect(capture.bodyString == #"{"note":null}"#)
  }

  @Test
  func updateOmitsAColumnItNeverNames() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .update { $0.task = "done" }.eq(\.id, 1).execute()
    #expect(capture.bodyString == #"{"task":"done"}"#)
  }

  @Test
  func anUpdateBuiltAheadOfTimeCanBeHandedToTheSource() async throws {
    // The payload is a value, so one layer can decide the change and another can send it.
    let update = PostgrestUpdate<Todo> { $0.note = nil }
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self).update(update).eq(\.id, 1).execute()
    #expect(capture.bodyString == #"{"note":null}"#)
  }

  @Test
  func deleteScopesByKeyPath() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self).delete().eq(\.id, 1).execute()
    #expect(capture.query?.contains("id=eq.1") == true)
  }

  @Test
  func returningDecodesRows() async throws {
    let capture = QueryCapture(body: #"[{"id":1,"task":"buy milk","is_done":false}]"#)
    let rows = try await capture.client.from(Todo.self)
      .insert(Todo.Draft(task: "buy milk", isDone: nil)).returning().execute().value
    #expect(rows.first?.task == "buy milk")
  }
}
