//
//  PostgrestAggregate.swift
//  PostgREST
//
//  Created by Guilherme Souza on 26/08/26.
//

extension PostgrestDerivedExpression where Value == Int, Position == PostgrestSelectOnly {
  /// `count()` — counts rows rather than values of a column.
  public static var countAll: Self { Self(embed: nil, inner: "count()") }
}

/// The five aggregate functions, each declared once and correct for a stored column, a JSON path
/// and either embed direction alike.
///
/// The result is **select position only**: PostgREST has no `HAVING`, and rejects an aggregate in
/// `order`, so filtering or ordering by one is a compile error. Grouping needs nothing declared —
/// selecting a plain column alongside an aggregate groups by it.
///
/// > Important: Requires PostgREST's `db-aggregates-enabled` setting. It is on for hosted
/// > Supabase and off by default when self-hosting.
///
/// > Important: The response is an array of objects keyed by the function name, not a scalar —
/// > `{"total":[{"sum":150}]}` for `select=total:children(amount.sum())`. Decode accordingly.
///
/// ## Decoding an empty result
///
/// `sum`, `avg`, `min` and `max` come back `null` when no rows match, so decode them as optionals.
/// Only `count` is exempt — it is `0`. Selecting the aggregate on its own still returns one row,
/// because a query with no grouping column has nothing to group by:
///
/// ```
/// ?select=amount.sum(),amount.count()&id=eq.99999   -> [{"sum":null,"count":0}]
/// ?select=count()&id=eq.99999                       -> [{"count":0}]
/// ?select=category,amount.sum()&id=eq.99999         -> []
/// ```
///
/// Adding a grouping column is what removes the row entirely, so a decoder written against the
/// grouped shape never sees the `null` and one written against the bare shape always can.
///
/// The result's `Value` is the *non-optional* type. It types the expression, not the response —
/// nothing in the SDK decodes through it — so it stays non-optional for the same reason a nullable
/// column's ``PostgrestColumn`` does: an optional `Value` would strip the operators from anything
/// chained off it.
extension PostgrestColumnExpression {
  /// The sum of this expression across the group, typed `Double` whatever the column's type.
  ///
  /// > Important: The wire value is a JSON integer, so past 2^53 a `Double` rounds it silently.
  /// > When a total can get that large, alias the aggregate in `select` and decode that field as
  /// > `Int` or `Decimal`.
  public func sum() -> PostgrestDerivedExpression<Root, Double, PostgrestSelectOnly> {
    _deriving(".sum()")
  }

  /// The mean of this expression across the group.
  public func avg() -> PostgrestDerivedExpression<Root, Double, PostgrestSelectOnly> {
    _deriving(".avg()")
  }

  /// The smallest value of this expression in the group, keeping the expression's own type.
  public func min() -> PostgrestDerivedExpression<Root, Value, PostgrestSelectOnly> {
    _deriving(".min()")
  }

  /// The largest value of this expression in the group.
  public func max() -> PostgrestDerivedExpression<Root, Value, PostgrestSelectOnly> {
    _deriving(".max()")
  }

  /// How many non-null values of this expression are in the group.
  public func count() -> PostgrestDerivedExpression<Root, Int, PostgrestSelectOnly> {
    _deriving(".count()")
  }
}
