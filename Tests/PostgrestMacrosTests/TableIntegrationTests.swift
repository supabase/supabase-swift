//
//  TableIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/08/26.
//

import Foundation
import PostgrestMacros
import Testing

// Declared at file scope on purpose. `@Table` attaches an extension, and Swift does not allow an
// extension of a type nested inside another type, so annotating a nested struct fails to compile.
@Table("todos")
struct IntegrationTodo: Hashable {
  @PrimaryKey var id: Int
  var task: String
  @Default var isDone: Bool
  @Column("due_at") var dueDate: Date?
}

@Table("active_todos", readOnly: true)
struct IntegrationActiveTodo {
  var id: Int
  var task: String
}

@Suite
struct TableIntegrationTests {
  typealias Todo = IntegrationTodo

  @Test
  func macroSuppliesTheRelationName() {
    #expect(Todo.relationName == "todos")
    #expect(Todo.schema == "public")
    #expect(Todo.selectString == "*")
  }

  @Test
  func macroMapsKeyPathsToColumns() {
    #expect(Todo.columnName(for: \.id) == "id")
    #expect(Todo.columnName(for: \.isDone) == "is_done")
    #expect(Todo.columnName(for: \.dueDate) == "due_at")
  }

  @Test
  func insertExcludesThePrimaryKeyAndUsesColumnNames() throws {
    let data = try JSONEncoder().encode(Todo.Insert(task: "buy milk", isDone: false))
    let json = String(decoding: data, as: UTF8.self)
    #expect(json.contains("\"id\"") == false)
    #expect(json.contains("\"is_done\"") == true)
    #expect(json.contains("\"isDone\"") == false)
  }

  @Test
  func aNilOptionalIsOmittedSoTheDatabaseDefaultApplies() throws {
    // `@Default var isDone` is optional in `Insert` precisely so it can be left out. Encoding it
    // as `null` would insert NULL instead of letting the column default apply.
    let data = try JSONEncoder().encode(Todo.Insert(task: "buy milk"))
    let json = String(decoding: data, as: UTF8.self)
    #expect(json == #"{"task":"buy milk"}"#)
  }

  @Test
  func aPartialUpdateNamesOnlyWhatItChanges() throws {
    let data = try JSONEncoder().encode(Todo.Update(isDone: true))
    let json = String(decoding: data, as: UTF8.self)
    #expect(json == #"{"is_done":true}"#)
  }

  @Test
  func aMacroTypeFlowsThroughTheTypedQuery() async throws {
    let capture = RequestCapture(
      body: #"[{"id":1,"task":"buy milk","is_done":false,"due_at":null}]"#
    )
    let todos = try await capture.client
      .from(Todo.self)
      .select()
      .eq(\.isDone, false)
      .order(\.id, ascending: false)
      .execute()
      .value

    #expect(todos == [Todo(id: 1, task: "buy milk", isDone: false, dueDate: nil)])
    #expect(capture.path?.hasSuffix("/todos") == true)
    #expect(capture.query?.contains("select=*") == true)
    #expect(capture.query?.contains("is_done=eq.false") == true)
    #expect(capture.query?.contains("id.desc") == true)
  }

  @Test
  func aMacroTypeFlowsThroughATypedWrite() async throws {
    let capture = RequestCapture()
    _ = try await capture.client
      .from(Todo.self)
      .insert(Todo.Insert(task: "buy milk"))
      .execute()

    #expect(capture.path?.hasSuffix("/todos") == true)
    #expect(capture.bodyString == #"{"task":"buy milk"}"#)
  }

  @Test
  func aReadOnlyRelationIsStillQueryable() async throws {
    let capture = RequestCapture(body: #"[{"id":1,"task":"buy milk"}]"#)
    let rows = try await capture.client
      .from(IntegrationActiveTodo.self)
      .select()
      .eq(\.task, "buy milk")
      .execute()
      .value

    #expect(rows.count == 1)
    #expect(capture.path?.hasSuffix("/active_todos") == true)
    #expect(capture.query?.contains("task=eq.buy milk") == true)
  }
}
