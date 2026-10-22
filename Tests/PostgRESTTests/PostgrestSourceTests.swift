//
//  PostgrestSourceTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/08/26.
//

import Foundation
import Testing

@_spi(Experimental) @testable import PostgREST

@Suite
struct PostgrestSourceTests {
  struct Todo: _PostgrestRelation {
    static let relationName = "todos"
    static let selectString = "*"

    var id: Int
    var task: String

    struct Columns: Sendable {
      let id = _PostgrestColumn<Todo, Int>("id")
      let task = _PostgrestColumn<Todo, String>("task")
    }

    static let columns = Columns()
  }

  @Test
  func fromUsesTheRelationName() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self).select().execute()
    #expect(capture.path?.hasSuffix("/todos") == true)
    #expect(capture.query?.contains("select=*") == true)
  }

  @Test
  func selectDecodesIntoTheRelationType() async throws {
    let capture = QueryCapture(body: #"[{"id":1,"task":"buy milk"}]"#)
    let todos = try await capture.client.from(Todo.self).select().execute().value
    #expect(todos.count == 1)
    #expect(todos.first?.task == "buy milk")
  }
}
