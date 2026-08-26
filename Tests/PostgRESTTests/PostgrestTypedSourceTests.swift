//
//  PostgrestTypedSourceTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/08/26.
//

import Foundation
import Testing

@testable import PostgREST

@Suite
struct PostgrestTypedSourceTests {
  struct Todo: PostgrestRelation {
    static let relationName = "todos"
    static let schema = "public"
    static let selectString = "*"

    var id: Int
    var task: String

    static func columnName(for keyPath: PartialKeyPath<Self>) -> String {
      switch keyPath {
      case \Self.id: "id"
      case \Self.task: "task"
      default: fatalError("unmapped key path")
      }
    }
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
