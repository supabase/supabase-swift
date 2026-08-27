//
//  PostgrestColumnExpressionTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 26/08/26.
//

import Foundation
import Testing

@testable import PostgREST

@Suite
struct PostgrestColumnExpressionTests {
  struct Todo: PostgrestRelation {
    static let relationName = "todos"
    static let schema = "public"
    static let selectString = "*"

    var id: Int
    var isDone: Bool
    var dueDate: Date?

    struct Columns: Sendable {
      let id = PostgrestColumn<Todo, Int>("id")
      let isDone = PostgrestColumn<Todo, Bool>("is_done")
      let dueDate = PostgrestNullableColumn<Todo, Date>("due_at")
    }

    static let columns = Columns()
  }

  @Test
  func aColumnRendersItsDatabaseName() {
    #expect(Todo.columns.isDone.postgrestExpression == "is_done")
    #expect(Todo.columns.dueDate.postgrestExpression == "due_at")
  }

  @Test
  func aColumnCarriesItsValueType() {
    #expect(type(of: Todo.columns.isDone).Value.self == Bool.self)
  }

  /// `var dueDate: Date?` gives `Value == Date`, so operators take a non-optional operand.
  @Test
  func aNullableColumnCarriesItsWrappedType() {
    #expect(type(of: Todo.columns.dueDate).Value.self == Date.self)
  }

  /// A plain column sits in all three positions; casts, aggregates and to-many projections are
  /// select-only.
  @Test
  func bothColumnKindsAreSelectableFilterableAndOrderable() {
    #expect((Todo.columns.id as Any) is any PostgrestFilterableExpression)
    #expect((Todo.columns.id as Any) is any PostgrestOrderableExpression)
    #expect((Todo.columns.dueDate as Any) is any PostgrestFilterableExpression)
    #expect((Todo.columns.dueDate as Any) is any PostgrestOrderableExpression)
  }
}
