//
//  DependencyBoundaryTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 09/10/26.
//

import Foundation
import Testing

// No `@testable`, and no `PostgrestMacros`: `PostgRESTTests` does not depend on it. This file
// compiling is the main assertion — the typed API works through its public surface alone, with a
// hand-written conformance, the way an app that never imports the macros would use it.
@_spi(Experimental) import PostgREST

@Suite
struct DependencyBoundaryTests {
  struct Todo: _PostgrestWritableRelation, _PostgrestKeyedRelation {
    static let relationName = "todos"
    static let selectString = "*"
    static let primaryKeyColumns = ["id"]

    var id: Int
    var task: String
    var isDone: Bool

    enum CodingKeys: String, CodingKey {
      case id
      case task
      case isDone = "is_done"
    }

    struct Columns: Sendable {
      let id = _PostgrestColumn<Todo, Int>("id")
      let task = _PostgrestColumn<Todo, String>("task")
      let isDone = _PostgrestColumn<Todo, Bool>("is_done")
    }

    static let columns = Columns()

    struct Draft: Encodable, Sendable {
      var task: String
    }
  }

  @Test
  func readsWithAHandWrittenConformance() async throws {
    let capture = QueryCapture(body: #"[{"id":1,"task":"buy milk","is_done":false}]"#)

    let todos = try await capture.client.from(Todo.self)
      .select()
      .where { $0.isDone.eq(false) }
      .execute()
      .value

    #expect(todos.map(\.task) == ["buy milk"])
    #expect(capture.path?.hasSuffix("/todos") == true)
    #expect(capture.query?.contains("is_done=eq.false") == true)
  }

  @Test
  func writesWithAHandWrittenConformance() async throws {
    let capture = QueryCapture()

    _ = try await capture.client.from(Todo.self).insert(Todo.Draft(task: "buy milk")).execute()

    #expect(capture.httpMethod == "POST")
    #expect(capture.bodyString?.contains(#""task":"buy milk""#) == true)
  }
}
