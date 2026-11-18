//
//  PostgrestUpdateTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 25/08/26.
//

import CustomDump
import Foundation
import Helpers
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
    var remindAt: Date
    var snoozedUntil: Date?

    enum CodingKeys: String, CodingKey {
      case id
      case task
      case dueAt = "due_at"
      case remindAt = "remind_at"
      case snoozedUntil = "snoozed_until"
    }

    struct Columns: Sendable {
      let id = _PostgrestColumn<Todo, Int>("id")
      let task = _PostgrestColumn<Todo, String>("task")
      let dueAt = _PostgrestNullableColumn<Todo, String>("due_at")
      let remindAt = _PostgrestColumn<Todo, Date>("remind_at")
      let snoozedUntil = _PostgrestNullableColumn<Todo, Date>("snoozed_until")
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

  /// A `Date` must reach the encoder's date strategy. Encoding it through its own
  /// `encode(to:)` bypasses the strategy and sends seconds since 2001 as a number.
  @Test
  func aDateUsesTheEncodersDateStrategy() throws {
    let date = Date(timeIntervalSince1970: 0)
    let update = _PostgrestUpdate<Todo> {
      $0.remindAt = date
      $0.snoozedUntil = date
    }
    let body = try JSONEncoder.supabase().encode(update)
    let decoded = try JSONDecoder().decode([String: JSONValue].self, from: body)
    #expect(
      decoded == [
        "remind_at": .string(date.iso8601String),
        "snoozed_until": .string(date.iso8601String),
      ]
    )
  }

  @Test
  func aKeyColumnCanBeAssigned() throws {
    let update = _PostgrestUpdate<Todo> { $0.id = 2 }
    expectNoDifference(try encoded(update), ["id": 2])
  }
}
