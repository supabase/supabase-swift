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

    struct Columns: Sendable {
      let id = PostgrestColumn<Todo, Int>("id")
      let task = PostgrestColumn<Todo, String>("task")
      let isDone = PostgrestColumn<Todo, Bool>("is_done")
    }

    static let columns = Columns()

    struct Draft: Encodable, Sendable {
      var task: String
      var isDone: Bool?
    }
  }

  @Test
  func aRelationIsAlsoASelection() {
    func selectString<T: PostgrestSelection>(of type: T.Type) -> String { T.selectString }
    #expect(selectString(of: Todo.self) == "*")
  }
}
