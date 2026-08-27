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
  struct Todo: PostgrestWritableRelation {
    static let relationName = "todos"
    static let schema = "public"
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
      let id = PostgrestColumn<Todo, Int>("id")
      let task = PostgrestColumn<Todo, String>("task")
      let dueAt = PostgrestNullableColumn<Todo, String>("due_at")
    }

    static let columns = Columns()

    struct Draft: Encodable, Sendable {
      var task: String
    }
  }

  /// Decodes an encoded payload back into a key/value map, because `JSONEncoder` does not
  /// preserve the key order of a dictionary-backed keyed container. Comparing the JSON text
  /// would make a passing test depend on hash ordering.
  private func encoded(_ update: PostgrestUpdate<Todo>) throws -> [String: JSONValue] {
    try JSONDecoder().decode([String: JSONValue].self, from: JSONEncoder().encode(update))
  }

  @Test
  func assigningNilSendsAnExplicitNull() throws {
    let update = PostgrestUpdate<Todo> { $0.dueAt = nil }
    expectNoDifference(try encoded(update), ["due_at": .null])
  }

  /// The expected keys are derived from `Todo.columns` rather than hardcoded, so this fails if
  /// the subscript ever reads a different source of truth than filters do. `dueAt` is the case
  /// that matters: its wire name (`due_at`) differs from its Swift name.
  @Test
  func assignmentsResolveThroughTheColumnNamespace() throws {
    let update = PostgrestUpdate<Todo> {
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
    let update = PostgrestUpdate<Todo> { $0.task = "buy oat milk" }
    expectNoDifference(try encoded(update), ["task": "buy oat milk"])
  }

  @Test
  func clearingAndSettingCoexistInOnePayload() throws {
    let update = PostgrestUpdate<Todo> {
      $0.task = "buy oat milk"
      $0.dueAt = nil
    }
    expectNoDifference(try encoded(update), ["task": "buy oat milk", "due_at": .null])
  }

  @Test
  func theLastAssignmentToAColumnWins() throws {
    let update = PostgrestUpdate<Todo> {
      $0.task = "first"
      $0.task = "second"
    }
    expectNoDifference(try encoded(update), ["task": "second"])
  }

  @Test
  func anUpdateThatNamesNothingIsEmpty() throws {
    let update = PostgrestUpdate<Todo> { _ in }
    #expect(update.isEmpty)
    expectNoDifference(try encoded(update), [:])
  }

  @Test
  func aKeyColumnCanBeAssigned() throws {
    // SDK-1607: renaming a natural key is a real operation, so the key is assignable like any
    // other column. Targeting is the filter's job, not the payload's.
    let update = PostgrestUpdate<Todo> { $0.id = 2 }
    expectNoDifference(try encoded(update), ["id": 2])
  }
}
