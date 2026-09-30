//
//  PostgrestAggregateTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 26/08/26.
//

import Foundation
import Testing

@testable import PostgREST

@Suite
struct PostgrestAggregateTests {
  struct Order: PostgrestRelation {
    static let relationName = "orders"
    static let schema = "public"
    static let selectString = "*"

    var amount: Double
    var quantity: Int

    struct Columns: Sendable {
      let amount = PostgrestColumn<Order, Double>("amount")
      let quantity = PostgrestColumn<Order, Int>("quantity")
    }

    static let columns = Columns()
  }

  @Test
  func aggregatesRenderTheirFunctionSuffix() {
    let amount = Order.columns.amount
    #expect(amount.sum().postgrestExpression == "amount.sum()")
    #expect(amount.avg().postgrestExpression == "amount.avg()")
    #expect(amount.min().postgrestExpression == "amount.min()")
    #expect(amount.max().postgrestExpression == "amount.max()")
    #expect(amount.count().postgrestExpression == "amount.count()")
  }

  /// `sum` and `avg` widen to `Double` whatever the column's type; `min` and `max` keep it, and
  /// `count` is always an `Int`.
  @Test
  func aggregatesCarryTheRightResultType() {
    #expect(type(of: Order.columns.quantity.sum()).Value.self == Double.self)
    #expect(type(of: Order.columns.quantity.avg()).Value.self == Double.self)
    #expect(type(of: Order.columns.quantity.min()).Value.self == Int.self)
    #expect(type(of: Order.columns.quantity.max()).Value.self == Int.self)
    #expect(type(of: Order.columns.quantity.count()).Value.self == Int.self)
  }

  /// `Value` is the non-optional result type: it types the expression, not the response. An
  /// aggregate over zero matching rows comes back `null` on the wire (`count` excepted), and the
  /// caller decodes that as an optional — the wrapped-type invariant here matches
  /// ``PostgrestColumn``'s, where an optional `Value` strips the operators from anything chained
  /// off it.
  @Test
  func theResultTypeStaysNonOptional() {
    #expect(type(of: Order.columns.amount.sum()).Value.self != Double?.self)
    #expect(type(of: Order.columns.amount.min()).Value.self != Double?.self)
  }

  /// `count()` with no column counts rows, so it takes no argument and is a static.
  @Test
  func countAllRendersWithNoColumn() {
    #expect(PostgrestAggregate<Order, Int>.countAll.postgrestExpression == "count()")
  }

  /// PostgREST has no `HAVING` and cannot order by an aggregate. Neither call must compile:
  ///
  ///     .where { $0.amount.sum().gt(100.0) }   // no member 'gt'
  ///     .order { $0.amount.sum().desc() }      // no member 'desc'
  @Test
  func anAggregateIsSelectableAndNothingElse() {
    let sum = Order.columns.amount.sum()
    #expect((sum as Any) is any PostgrestFilterableExpression == false)
    #expect((sum as Any) is any PostgrestOrderableExpression == false)
  }
}
