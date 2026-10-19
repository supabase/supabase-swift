//
//  SelectionIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/08/26.
//

import Foundation
@_spi(Experimental) import PostgrestMacros
import Testing

@Table("todos")
struct SelectionTodo {
  @PrimaryKey var id: Int
  var task: String
  @Default var isDone: Bool
  @Column("due_at") var dueDate: Date?
}

@SelectionOf(SelectionTodo.self)
struct SelectionTodoSummary: Hashable {
  var id: Int
  var isDone: Bool
}

@SelectionOf(SelectionTodo.self)
struct SelectionTodoDueDate {
  @Column("due_at") var dueDate: Date?
}

@SelectionOf(SelectionTodo.self)
struct SelectionTodoInheritedColumn {
  var dueDate: Date?
}

@Table("orders")
struct SelectionOrder {
  @PrimaryKey var id: Int
  var category: String
  var amount: Double
  var tax: Double
}

@SelectionOf(SelectionOrder.self)
struct SelectionOrderTotals: Hashable {
  var category: String
  @Aggregate(.sum, of: \SelectionOrder.amount) var total: Double?
  @Aggregate(.sum, of: \SelectionOrder.tax) var taxTotal: Double?
  @Aggregate(.count) var rows: Int
}

extension SelectionOrder.Columns {
  var exactTotal: _PostgrestAggregate<SelectionOrder, Double> { amount.sum() }
}

@SelectionOf(SelectionOrder.self)
struct SelectionOrderExactTotal {
  var exactTotal: Int?
}

@Suite
struct SelectionIntegrationTests {
  typealias TodoSummary = SelectionTodoSummary

  @Test
  func selectStringListsTheDeclaredColumns() {
    #expect(TodoSummary.selectString == "id:id,is_done:is_done")
  }

  @Test
  func columnOverridesApply() {
    #expect(SelectionTodoDueDate.selectString == "due_at:due_at")
  }

  @Test
  func aSelectionInheritsTheRelationsColumnMapping() {
    #expect(SelectionTodoInheritedColumn.selectString == "due_date:due_at")
  }

  @Test
  func aSelectionNamesItsSource() {
    #expect(TodoSummary.Source.relationName == "todos")
  }

  @Test
  func aRelationIsItsOwnSource() {
    #expect(SelectionTodo.Source.relationName == "todos")
  }

  @Test
  func selectSendsTheSelectStringAndDecodesTheSelection() async throws {
    let capture = RequestCapture(body: #"[{"id":1,"is_done":false}]"#)
    let rows = try await capture.client
      .from(SelectionTodo.self)
      .select(TodoSummary.self)
      .where { $0.isDone.eq(false) }
      .execute()
      .value

    #expect(rows == [TodoSummary(id: 1, isDone: false)])
    #expect(capture.path?.hasSuffix("/todos") == true)
    #expect(capture.query?.contains("select=id:id,is_done:is_done") == true)
    #expect(capture.query?.contains("is_done=eq.false") == true)
  }

  @Test
  func aColumnsMemberSelectsUnderThePropertyName() {
    #expect(SelectionOrderExactTotal.selectString == "exact_total:amount.sum()")
  }

  @Test
  func aggregatesGetTheirOwnKeys() {
    #expect(
      SelectionOrderTotals.selectString
        == "category:category,total:amount.sum(),tax_total:tax.sum(),rows:count()"
    )
  }

  @Test
  func aggregateSelectionDecodesTheGroupedRows() async throws {
    let capture = RequestCapture(
      body: #"[{"category":"books","total":10.5,"tax_total":2,"rows":3}]"#
    )
    let rows = try await capture.client
      .from(SelectionOrder.self)
      .select(SelectionOrderTotals.self)
      .execute()
      .value

    #expect(rows == [SelectionOrderTotals(category: "books", total: 10.5, taxTotal: 2, rows: 3)])
  }
}
