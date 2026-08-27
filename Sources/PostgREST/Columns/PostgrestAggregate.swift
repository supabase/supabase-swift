//
//  PostgrestAggregate.swift
//  PostgREST
//
//  Created by Guilherme Souza on 26/08/26.
//

/// An aggregate function applied to an expression — **select position only**.
///
/// PostgREST has no `HAVING`, and rejects an aggregate in `order`, so filtering or ordering by
/// one is a compile error. Grouping needs nothing declared: selecting a plain column alongside an
/// aggregate groups by it.
///
/// > Important: Requires PostgREST's `db-aggregates-enabled` setting. It is on for hosted
/// > Supabase and off by default when self-hosting.
///
/// > Important: The response is an array of objects keyed by the function name, not a scalar —
/// > `{"total":[{"sum":150}]}` for `select=total:children(amount.sum())`. Decode accordingly.
public struct PostgrestAggregate<Root: PostgrestRelation, Value>: PostgrestColumnExpression {
  public let postgrestExpression: String

  init(_ expression: String) {
    self.postgrestExpression = expression
  }
}

extension PostgrestAggregate where Value == Int {
  /// `count()` — counts rows rather than values of a column.
  public static var countAll: Self { Self("count()") }
}

extension PostgrestColumnExpression {
  /// The sum of this expression across the group, typed `Double` whatever the column's type.
  ///
  /// > Important: The wire value is a JSON integer, so past 2^53 a `Double` rounds it silently.
  /// > When a total can get that large, alias the aggregate in `select` and decode that field as
  /// > `Int` or `Decimal`.
  public func sum() -> PostgrestAggregate<Root, Double> {
    PostgrestAggregate("\(postgrestExpression).sum()")
  }

  /// The mean of this expression across the group.
  public func avg() -> PostgrestAggregate<Root, Double> {
    PostgrestAggregate("\(postgrestExpression).avg()")
  }

  /// The smallest value of this expression in the group, keeping the expression's own type.
  public func min() -> PostgrestAggregate<Root, Value> {
    PostgrestAggregate("\(postgrestExpression).min()")
  }

  /// The largest value of this expression in the group.
  public func max() -> PostgrestAggregate<Root, Value> {
    PostgrestAggregate("\(postgrestExpression).max()")
  }

  /// How many non-null values of this expression are in the group.
  ///
  /// For a count of rows rather than of values, use ``PostgrestAggregate/countAll``.
  public func count() -> PostgrestAggregate<Root, Int> {
    PostgrestAggregate("\(postgrestExpression).count()")
  }
}
