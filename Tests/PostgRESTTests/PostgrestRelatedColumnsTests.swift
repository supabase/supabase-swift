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
  struct Order: PostgrestRelation {
    static let relationName = "orders"
    static let schema = "public"
    static let selectString = "*"

    var id: Int
    var todoID: Int
    var amount: Double

    struct Columns: Sendable {
      let id = PostgrestColumn<Order, Int>("id")
      let todoID = PostgrestColumn<Order, Int>("todo_id")
      let amount = PostgrestColumn<Order, Double>("amount")
      let shippedAt = PostgrestNullableColumn<Order, Date>("shipped_at")
      // The to-one direction of the same pair: many orders per todo, one todo per order.
      let todo = PostgrestToOneRelation<Order, Todo>("todo")
    }

    static let columns = Columns()
  }

  struct Todo: PostgrestRelation {
    static let relationName = "todos"
    static let schema = "public"
    static let selectString = "*"

    var id: Int
    var title: String

    struct Columns: Sendable {
      let id = PostgrestColumn<Todo, Int>("id")
      let title = PostgrestColumn<Todo, String>("title")
      // Deliberately named `name`: every public member of the relation type shadows a projected
      // column of the same name, so this is the case that regressed.
      let name = PostgrestColumn<Todo, String>("name")
      // Numeric, so an aggregate over the to-one direction has something meaningful to sum.
      let amount = PostgrestColumn<Todo, Double>("amount")
      // What the generator emits from postgres-meta's foreign-key metadata: the relationship,
      // declared once, checked at every use.
      let orders = PostgrestToManyRelation<Todo, Order>("orders")
    }

    static let columns = Columns()
  }

  @Test
  func aProjectedColumnWrapsInTheEmbedName() {
    #expect(Todo.columns.orders.amount.postgrestExpression == "orders(amount)")
  }

  /// `@dynamicMemberLookup` only fires when no real member matches, so any public member of the
  /// relation type wins over a projected column spelled the same way. With the property named
  /// `name`, `Order.columns.todo.name` type-checked as the embed's own name string and the
  /// column was unreachable — a silently wrong `select`, not an error.
  @Test
  func aProjectedColumnNamedLikeARelationMemberStillProjects() {
    let projected = Order.columns.todo.name
    #expect(projected.postgrestExpression == "todo(name)")
    #expect(type(of: projected).Value.self == String.self)
    // The embed name is still readable, under a name no column will collide with.
    #expect(Order.columns.todo.postgrestEmbedName == "todo")
  }

  /// The aggregate goes inside the parentheses — `orders(amount.sum())`, never
  /// `orders(amount).sum()`. PostgREST answers 200 for the latter and silently ignores the
  /// `.sum()`, so every aggregate is shadowed to keep the function inside.
  @Test
  func anAggregateOverAnEmbedRendersInsideTheParentheses() {
    #expect(Todo.columns.orders.amount.sum().postgrestExpression == "orders(amount.sum())")
    #expect(Todo.columns.orders.id.count().postgrestExpression == "orders(id.count())")
    #expect(Todo.columns.orders.amount.avg().postgrestExpression == "orders(amount.avg())")
    #expect(Todo.columns.orders.id.min().postgrestExpression == "orders(id.min())")
    #expect(Todo.columns.orders.id.max().postgrestExpression == "orders(id.max())")
  }

  /// Same for a cast: unshadowed it would render `orders(amount)::text`, which PostgREST answers
  /// 200 with the cast dropped.
  @Test
  func aCastOverAnEmbedRendersInsideTheParentheses() {
    #expect(
      Todo.columns.orders.amount.cast(to: .text).postgrestExpression == "orders(amount::text)")
  }

  /// `jsonText(_:)` is declared on the base protocol too, so it needs the same shadow.
  @Test
  func aJSONTextPathOverAnEmbedRendersInsideTheParentheses() {
    #expect(
      Todo.columns.orders.amount.jsonText("k").postgrestExpression == "orders(amount->>k)")
  }

  /// `jsonObject(_:)` is declared on the base protocol too, so it needs the same shadow.
  @Test
  func aJSONObjectPathOverAnEmbedRendersInsideTheParentheses() {
    #expect(
      Todo.columns.orders.amount.jsonObject("k").postgrestExpression == "orders(amount->k)")
  }

  @Test
  func aProjectedColumnKeepsItsValueType() {
    #expect(type(of: Todo.columns.orders.amount).Value.self == Double.self)
    #expect(type(of: Todo.columns.orders.amount.sum()).Value.self == Double.self)
  }

  /// One subscript, generic over the column kind, so a nullable embedded column needs no
  /// second declaration.
  @Test
  func aNullableEmbeddedColumnProjectsThroughTheSameSubscript() {
    #expect(Todo.columns.orders.shippedAt.postgrestExpression == "orders(shipped_at)")
    #expect(type(of: Todo.columns.orders.shippedAt).Value.self == Date.self)
  }

  /// An embedded column filters with dot notation, a different string from the select form. It is
  /// not filterable directly — SDK-1575's embed scope uses this:
  ///
  ///     .where { $0.orders.id.eq(7) }
  ///     -> value of type 'PostgrestToManyColumn<…>' has no member 'eq'
  ///
  /// Nor orderable. Checked on an erased value, since a positive `is` on the concrete type would
  /// be a compile-time truism.
  @Test
  func theFilterFormIsDottedAndSeparate() {
    #expect(Todo.columns.orders.id.embeddedFilterName == "orders.id")
    #expect(Todo.columns.orders.id.postgrestExpression == "orders(id)")
    #expect((Todo.columns.orders.id as Any) is any PostgrestFilterableExpression == false)
    #expect((Todo.columns.orders.id as Any) is any PostgrestOrderableExpression == false)
  }

  /// A to-one projection renders and filters exactly like a to-many one — the difference between
  /// them is orderability, not selection.
  @Test
  func aToOneProjectionWrapsInTheEmbedNameAndFilterForm() {
    #expect(Order.columns.todo.title.postgrestExpression == "todo(title)")
    #expect(Order.columns.todo.title.embeddedFilterName == "todo.title")
    #expect((Order.columns.todo.title as Any) is any PostgrestFilterableExpression == false)
  }

  /// The reason `PostgrestToOneRelation` is a separate type: its projections are orderable, while
  /// a to-many projection's `order` is a 400 PGRST118. Proven behaviorally, by rendering
  /// `asc()`/`desc()`, rather than with an `is` check that asserts nothing on a concrete type.
  @Test
  func aToOneProjectionIsOrderableButAToManyProjectionIsNot() {
    #expect(Order.columns.todo.title.asc().rendered == "todo(title).asc")
    // A direction is optional here too.
    #expect(
      PostgrestOrdering<Order>(
        column: Order.columns.todo.title.postgrestExpression, ascending: nil
      ).rendered == "todo(title)")
    #expect(Order.columns.todo.title.desc().rendered == "todo(title).desc")
    #expect((Todo.columns.orders.amount as Any) is any PostgrestOrderableExpression == false)
  }

  /// A to-one embed needs the same shadowing as a to-many one; both would otherwise render
  /// `todo(amount)::text` instead of `todo(amount::text)`.
  @Test
  func aToOneProjectionShadowsCastAndJSONPathToo() {
    #expect(Order.columns.todo.id.cast(to: .text).postgrestExpression == "todo(id::text)")
    #expect(Order.columns.todo.id.jsonText("k").postgrestExpression == "todo(id->>k)")
    #expect(Order.columns.todo.id.jsonObject("k").postgrestExpression == "todo(id->k)")
  }

  /// A cast of a to-one projection must not be orderable even though the projection is, which is
  /// why ``PostgrestToOneColumn/cast(to:)`` returns `PostgrestToOneDerivedColumn` rather than
  /// `Self`. A JSON path stays orderable. Proven behaviorally by calling `asc()`.
  @Test
  func aToOneCastIsNotOrderableButAToOneJSONPathIs() {
    #expect(
      (Order.columns.todo.id.cast(to: .text) as Any) is any PostgrestOrderableExpression == false)
    #expect(Order.columns.todo.id.jsonText("k").asc().rendered == "todo(id->>k).asc")
  }

  /// A to-one projection has the identical rendering bug if unshadowed: PostgREST answers 200 for
  /// `probe_parent(id).sum()` and ignores the `.sum()`, while `probe_parent(id.sum())` applies it.
  @Test
  func anAggregateOverAToOneProjectionRendersInsideTheParentheses() {
    #expect(Order.columns.todo.id.sum().postgrestExpression == "todo(id.sum())")
    #expect(Order.columns.todo.id.avg().postgrestExpression == "todo(id.avg())")
    #expect(Order.columns.todo.id.min().postgrestExpression == "todo(id.min())")
    #expect(Order.columns.todo.id.max().postgrestExpression == "todo(id.max())")
    #expect(Order.columns.todo.id.count().postgrestExpression == "todo(id.count())")
  }

  /// Both halves have to hold at once: the projection stays orderable, an aggregate of it does
  /// not. That is why `sum()` and its siblings return `PostgrestToOneDerivedColumn`. The negative
  /// half uses the erased form, since a positive `is` on a concrete type is a truism.
  @Test
  func aToOneAggregateIsNotOrderableEvenThoughTheProjectionIs() {
    #expect(Order.columns.todo.id.asc().rendered == "todo(id).asc")
    #expect((Order.columns.todo.id.sum() as Any) is any PostgrestOrderableExpression == false)
    #expect((Order.columns.todo.id.count() as Any) is any PostgrestOrderableExpression == false)
  }

  /// The point of `PostgrestToOneDerivedColumn`: it keeps `embed` and `inner` apart, so anything
  /// chained onto a cast or aggregate lands inside the embed's parentheses. Returning a flat
  /// `PostgrestCastColumn`/`PostgrestAggregate` put it outside, where PostgREST answers 200 and
  /// silently discards it — measured for all six outside forms. The inside form applies:
  /// `probe_parent(id.sum()::text)` returns `{"sum": "1"}`.
  @Test
  func aDerivedToOneChainStaysInsideTheEmbedParentheses() {
    #expect(
      Order.columns.todo.amount.sum().cast(to: .text).postgrestExpression
        == "todo(amount.sum()::text)")
    #expect(
      Order.columns.todo.id.cast(to: .text).jsonText("k").postgrestExpression
        == "todo(id::text->>k)")
    #expect(
      Order.columns.todo.id.sum().jsonObject("k").postgrestExpression == "todo(id.sum()->k)")
    #expect(Order.columns.todo.id.sum().sum().postgrestExpression == "todo(id.sum().sum())")
    #expect(
      Order.columns.todo.id.cast(to: .text).cast(to: .int).postgrestExpression
        == "todo(id::text::int)")
    #expect(
      Order.columns.todo.id.cast(to: .text).sum().postgrestExpression == "todo(id::text.sum())")
  }

  /// Landing the operation inside the parentheses does not make every chain valid — it makes an
  /// invalid one loud instead of silent. PostgREST accepts only `::` after an aggregate, so a
  /// second aggregate or a JSON path is a 400 rather than a quietly dropped operation. Nothing to
  /// assert against the server here; the point is that the SDK no longer renders a string
  /// PostgREST accepts and ignores.
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

  /// `PostgrestToOneDerivedColumn` is select position only, and has to stay that way: a cast and
  /// an aggregate are both 400 in `order`, and there is no `HAVING`. Asserted on an erased value,
  /// so it keeps failing if a later change adds either conformance.
  @Test
  func aDerivedToOneProjectionIsNeitherOrderableNorFilterable() {
    let fromCast = Order.columns.todo.id.cast(to: .text)
    let fromAggregate = Order.columns.todo.amount.sum()
    let chained = Order.columns.todo.amount.sum().cast(to: .text)

    for value in [fromCast as Any, fromAggregate as Any, chained as Any] {
      #expect(value is any PostgrestOrderableExpression == false)
      #expect(value is any PostgrestFilterableExpression == false)
      #expect(value is any PostgrestColumnExpression)
    }
  }

  /// A derived projection carries the `Value` the operation produces, not the column's: `sum()`
  /// widens to `Double`, `count()` is `Int`, `min()`/`max()` keep the column's type, and a cast
  /// takes its target's. That is what makes a wrong operand a compile error, not a decode failure.
  @Test
  func aDerivedToOneProjectionCarriesTheOperationsValueType() {
    #expect(type(of: Order.columns.todo.id.sum()).Value.self == Double.self)
    #expect(type(of: Order.columns.todo.id.count()).Value.self == Int.self)
    #expect(type(of: Order.columns.todo.id.min()).Value.self == Int.self)
    #expect(type(of: Order.columns.todo.id.cast(to: .text)).Value.self == String.self)
    #expect(type(of: Order.columns.todo.amount.sum().cast(to: .int)).Value.self == Int.self)
  }
}
