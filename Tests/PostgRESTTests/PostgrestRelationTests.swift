//
//  PostgrestRelationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/08/26.
//

import Testing

@testable import PostgREST

@Suite
struct PostgrestRelationTests {
  struct Todo: PostgrestWritableRelation {
    static let relationName = "todos"
    static let schema = "public"
    static let selectString = "*"

    var id: Int
    var task: String
    var isDone: Bool

    static func columnName(for keyPath: PartialKeyPath<Self>) -> String {
      switch keyPath {
      case \Self.id: "id"
      case \Self.task: "task"
      case \Self.isDone: "is_done"
      default: fatalError("unmapped key path")
      }
    }

    struct Draft: Encodable, Sendable {
      var task: String
      var isDone: Bool?
    }
  }

  @Test
  func columnNameMapsKeyPathToDatabaseColumn() {
    #expect(Todo.columnName(for: \.id) == "id")
    #expect(Todo.columnName(for: \.isDone) == "is_done")
  }

  @Test
  func aRelationIsAlsoASelection() {
    func selectString<T: PostgrestSelection>(of type: T.Type) -> String { T.selectString }
    #expect(selectString(of: Todo.self) == "*")
  }
}
