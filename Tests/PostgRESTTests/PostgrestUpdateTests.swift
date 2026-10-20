//
//  PostgrestUpdateTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 25/08/26.
//

import CustomDump
import Foundation
import Testing

@testable import PostgREST

@Suite
struct PostgrestUpdateTests {
  struct Todo: _PostgrestWritableRelation {
    static let relationName = "todos"
    static let selectString = "*"

    var id: Int
    var task: String
    var dueAt: String?

    enum CodingKeys: String, CodingKey {
      case id
      case task
      case dueAt = "due_at"
    }

    struct Columns: Sendable {
      let id = _PostgrestColumn<Todo, Int>("id")
      let task = _PostgrestColumn<Todo, String>("task")
      let dueAt = _PostgrestNullableColumn<Todo, String>("due_at")
    }

    static let columns = Columns()

    struct Draft: Encodable, Sendable {
      var task: String
    }
  }

  private func encoded(_ update: _PostgrestUpdate<Todo>) throws -> [String: JSONValue] {
    try JSONDecoder().decode([String: JSONValue].self, from: JSONEncoder().encode(update))
  }

  @Test
  func assigningNilSendsAnExplicitNull() throws {
    let update = _PostgrestUpdate<Todo> { $0.dueAt = nil }
    expectNoDifference(try encoded(update), ["due_at": .null])
  }

  @Test
  func assignmentsResolveThroughTheColumnNamespace() throws {
    let update = _PostgrestUpdate<Todo> {
      $0.task = "buy oat milk"
      $0.dueAt = nil
    }
    expectNoDifference(
      try encoded(update),
      [
        Todo.columns.task.postgrestExpression: "buy oat milk",
        Todo.columns.dueAt.postgrestExpression: .null,
      ]
    )
  }

  @Test
  func aColumnNeverAssignedIsAbsentFromTheBody() throws {
    let update = _PostgrestUpdate<Todo> { $0.task = "buy oat milk" }
    expectNoDifference(try encoded(update), ["task": "buy oat milk"])
  }

  @Test
  func clearingAndSettingCoexistInOnePayload() throws {
    let update = _PostgrestUpdate<Todo> {
      $0.task = "buy oat milk"
      $0.dueAt = nil
    }
    expectNoDifference(try encoded(update), ["task": "buy oat milk", "due_at": .null])
  }

  @Test
  func theLastAssignmentToAColumnWins() throws {
    let update = _PostgrestUpdate<Todo> {
      $0.task = "first"
      $0.task = "second"
    }
    expectNoDifference(try encoded(update), ["task": "second"])
  }

  @Test
  func anUpdateThatNamesNothingIsEmpty() throws {
    let update = _PostgrestUpdate<Todo> { _ in }
    #expect(update.isEmpty)
    expectNoDifference(try encoded(update), [:])
  }

  @Test
  func aKeyColumnCanBeAssigned() throws {
    let update = _PostgrestUpdate<Todo> { $0.id = 2 }
    expectNoDifference(try encoded(update), ["id": 2])
  }
}
