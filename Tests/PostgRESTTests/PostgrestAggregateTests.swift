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
  struct Order: _PostgrestRelation {
    static let relationName = "orders"
    static let selectString = "*"

    var amount: Double
    var quantity: Int

    struct Columns: Sendable {
      let amount = _PostgrestColumn<Order, Double>("amount")
      let quantity = _PostgrestColumn<Order, Int>("quantity")
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

  @Test
  func aggregatesCarryTheRightResultType() {
    #expect(type(of: Order.columns.quantity.sum()).Value.self == Double.self)
    #expect(type(of: Order.columns.quantity.avg()).Value.self == Double.self)
    #expect(type(of: Order.columns.quantity.min()).Value.self == Int.self)
    #expect(type(of: Order.columns.quantity.max()).Value.self == Int.self)
    #expect(type(of: Order.columns.quantity.count()).Value.self == Int.self)
  }

  @Test
  func theResultTypeStaysNonOptional() {
    #expect(type(of: Order.columns.amount.sum()).Value.self != Double?.self)
    #expect(type(of: Order.columns.amount.min()).Value.self != Double?.self)
  }

  @Test
  func countAllRendersWithNoColumn() {
    #expect(_PostgrestAggregate<Order, Int>.countAll.postgrestExpression == "count()")
  }

  @Test
  func anAggregateIsSelectableAndNothingElse() {
    let sum = Order.columns.amount.sum()
    #expect((sum as Any) is any _PostgrestFilterableExpression == false)
    #expect((sum as Any) is any _PostgrestOrderableExpression == false)
  }
}
