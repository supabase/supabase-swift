//
//  PostgrestRelatedColumnsTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 26/08/26.
//

import Foundation
import Testing

@testable import PostgREST

@Suite
struct PostgrestRelatedColumnsTests {
  struct Order: _PostgrestRelation {
    static let relationName = "orders"
    static let selectString = "*"

    var id: Int
    var todoID: Int
    var amount: Double

    struct Columns: Sendable {
      let id = _PostgrestColumn<Order, Int>("id")
      let todoID = _PostgrestColumn<Order, Int>("todo_id")
      let amount = _PostgrestColumn<Order, Double>("amount")
      let meta = _PostgrestColumn<Order, JSONValue>("meta")
      let shippedAt = _PostgrestNullableColumn<Order, Date>("shipped_at")
      let todo = _PostgrestToOneRelation<Order, Todo>("todo")
    }

    static let columns = Columns()
  }

  struct Todo: _PostgrestRelation {
    static let relationName = "todos"
    static let selectString = "*"

    var id: Int
    var title: String

    struct Columns: Sendable {
      let id = _PostgrestColumn<Todo, Int>("id")
      let title = _PostgrestColumn<Todo, String>("title")
      let name = _PostgrestColumn<Todo, String>("name")
      let amount = _PostgrestColumn<Todo, Double>("amount")
      let meta = _PostgrestColumn<Todo, JSONValue>("meta")
      let orders = _PostgrestToManyRelation<Todo, Order>("orders")
    }

    static let columns = Columns()
  }

  @Test
  func aProjectedColumnWrapsInTheEmbedName() {
    #expect(Todo.columns.orders.amount.postgrestExpression == "orders(amount)")
  }

  @Test
  func aProjectedColumnNamedLikeARelationMemberStillProjects() {
    let projected = Order.columns.todo.name
    #expect(projected.postgrestExpression == "todo(name)")
    #expect(type(of: projected).Value.self == String.self)
    #expect(Order.columns.todo.postgrestEmbedName == "todo")
  }

  @Test
  func anAggregateOverAnEmbedRendersInsideTheParentheses() {
    #expect(Todo.columns.orders.amount.sum().postgrestExpression == "orders(amount.sum())")
    #expect(Todo.columns.orders.id.count().postgrestExpression == "orders(id.count())")
    #expect(Todo.columns.orders.amount.avg().postgrestExpression == "orders(amount.avg())")
    #expect(Todo.columns.orders.id.min().postgrestExpression == "orders(id.min())")
    #expect(Todo.columns.orders.id.max().postgrestExpression == "orders(id.max())")
  }

  @Test
  func aCastOverAnEmbedRendersInsideTheParentheses() {
    #expect(
      Todo.columns.orders.amount.cast(to: .text).postgrestExpression == "orders(amount::text)")
  }

  @Test
  func aJSONTextPathOverAnEmbedRendersInsideTheParentheses() {
    #expect(
      Todo.columns.orders.meta.jsonText("k").postgrestExpression == #"orders(meta->>"k")"#)
  }

  @Test
  func aJSONObjectPathOverAnEmbedRendersInsideTheParentheses() {
    #expect(
      Todo.columns.orders.meta.jsonObject("k").postgrestExpression == #"orders(meta->"k")"#)
  }

  @Test
  func aProjectedColumnKeepsItsValueType() {
    #expect(type(of: Todo.columns.orders.amount).Value.self == Double.self)
    #expect(type(of: Todo.columns.orders.amount.sum()).Value.self == Double.self)
  }

  @Test
  func aNullableEmbeddedColumnProjectsThroughTheSameSubscript() {
    #expect(Todo.columns.orders.shippedAt.postgrestExpression == "orders(shipped_at)")
    #expect(type(of: Todo.columns.orders.shippedAt).Value.self == Date.self)
  }

  @Test
  func theFilterFormIsDottedAndSeparate() {
    #expect(Todo.columns.orders.id.embeddedFilterName == "orders.id")
    #expect(Todo.columns.orders.id.postgrestExpression == "orders(id)")
    #expect((Todo.columns.orders.id as Any) is any _PostgrestFilterableExpression == false)
    #expect((Todo.columns.orders.id as Any) is any _PostgrestOrderableExpression == false)
  }

  @Test
  func aToOneProjectionWrapsInTheEmbedNameAndFilterForm() {
    #expect(Order.columns.todo.title.postgrestExpression == "todo(title)")
    #expect(Order.columns.todo.title.embeddedFilterName == "todo.title")
    #expect((Order.columns.todo.title as Any) is any _PostgrestFilterableExpression == false)
  }

  @Test
  func aToOneProjectionIsOrderableButAToManyProjectionIsNot() {
    #expect(Order.columns.todo.title.asc().rendered == "todo(title).asc")
    #expect(
      _PostgrestOrdering<Order>(
        column: Order.columns.todo.title.postgrestExpression, ascending: nil
      ).rendered == "todo(title)")
    #expect(Order.columns.todo.title.desc().rendered == "todo(title).desc")
    #expect((Todo.columns.orders.amount as Any) is any _PostgrestOrderableExpression == false)
  }

  @Test
  func aToOneProjectionShadowsCastAndJSONPathToo() {
    #expect(Order.columns.todo.id.cast(to: .text).postgrestExpression == "todo(id::text)")
    #expect(Order.columns.todo.meta.jsonText("k").postgrestExpression == #"todo(meta->>"k")"#)
    #expect(Order.columns.todo.meta.jsonObject("k").postgrestExpression == #"todo(meta->"k")"#)
  }

  @Test
  func aToOneCastIsNotOrderableButAToOneJSONPathIs() {
    #expect(
      (Order.columns.todo.id.cast(to: .text) as Any) is any _PostgrestOrderableExpression == false)
    #expect(Order.columns.todo.meta.jsonText("k").asc().rendered == #"todo(meta->>"k").asc"#)
  }

  @Test
  func anAggregateOverAToOneProjectionRendersInsideTheParentheses() {
    #expect(Order.columns.todo.id.sum().postgrestExpression == "todo(id.sum())")
    #expect(Order.columns.todo.id.avg().postgrestExpression == "todo(id.avg())")
    #expect(Order.columns.todo.id.min().postgrestExpression == "todo(id.min())")
    #expect(Order.columns.todo.id.max().postgrestExpression == "todo(id.max())")
    #expect(Order.columns.todo.id.count().postgrestExpression == "todo(id.count())")
  }

  @Test
  func aToOneAggregateIsNotOrderableEvenThoughTheProjectionIs() {
    #expect(Order.columns.todo.id.asc().rendered == "todo(id).asc")
    #expect((Order.columns.todo.id.sum() as Any) is any _PostgrestOrderableExpression == false)
    #expect((Order.columns.todo.id.count() as Any) is any _PostgrestOrderableExpression == false)
  }

  @Test
  func aDerivedToOneChainStaysInsideTheEmbedParentheses() {
    #expect(
      Order.columns.todo.amount.sum().cast(to: .text).postgrestExpression
        == "todo(amount.sum()::text)")
    #expect(
      Order.columns.todo.meta.jsonObject("k").cast(to: .text).postgrestExpression
        == #"todo(meta->"k"::text)"#)
    #expect(
      Order.columns.todo.meta.jsonObject("a").jsonText("b").postgrestExpression
        == #"todo(meta->"a"->>"b")"#)
    #expect(Order.columns.todo.id.sum().sum().postgrestExpression == "todo(id.sum().sum())")
    #expect(
      Order.columns.todo.id.cast(to: .text).cast(to: .int).postgrestExpression
        == "todo(id::text::int)")
    #expect(
      Order.columns.todo.id.cast(to: .text).sum().postgrestExpression == "todo(id::text.sum())")
  }

  @Test
  func theSingleAppliedDerivedFormIsACastAfterAnAggregate() {
    #expect(
      Order.columns.todo.amount.avg().cast(to: .text).postgrestExpression
        == "todo(amount.avg()::text)")
    #expect(
      Order.columns.todo.id.min().cast(to: .text).postgrestExpression == "todo(id.min()::text)")
    #expect(
      Order.columns.todo.id.max().cast(to: .text).postgrestExpression == "todo(id.max()::text)")
    #expect(
      Order.columns.todo.id.count().cast(to: .text).postgrestExpression
        == "todo(id.count()::text)")
  }

  @Test
  func aDerivedToOneProjectionIsNeitherOrderableNorFilterable() {
    let fromCast = Order.columns.todo.id.cast(to: .text)
    let fromAggregate = Order.columns.todo.amount.sum()
    let chained = Order.columns.todo.amount.sum().cast(to: .text)

    for value in [fromCast as Any, fromAggregate as Any, chained as Any] {
      #expect(value is any _PostgrestOrderableExpression == false)
      #expect(value is any _PostgrestFilterableExpression == false)
      #expect(value is any _PostgrestColumnExpression)
    }
  }

  @Test
  func aDerivedToOneProjectionCarriesTheOperationsValueType() {
    #expect(type(of: Order.columns.todo.id.sum()).Value.self == Double.self)
    #expect(type(of: Order.columns.todo.id.count()).Value.self == Int.self)
    #expect(type(of: Order.columns.todo.id.min()).Value.self == Int.self)
    #expect(type(of: Order.columns.todo.id.cast(to: .text)).Value.self == String.self)
    #expect(type(of: Order.columns.todo.amount.sum().cast(to: .int)).Value.self == Int.self)
  }
}
