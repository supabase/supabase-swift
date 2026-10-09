//
//  PostgrestAggregate.swift
//  PostgREST
//
//  Created by Guilherme Souza on 26/08/26.
//

/// The aggregate functions PostgREST accepts in a `select` list.
///
/// A selection names one with `@Aggregate` from the `PostgrestMacros` module. Each case applies the
/// method of the same name, such as ``_PostgrestColumnExpression/sum()``.
public enum _PostgrestAggregateFunction: String, Sendable {
  case sum, avg, min, max, count

  /// The call as it appears in a `select` list, `sum()`.
  var call: String { "\(rawValue)()" }
}

extension _PostgrestDerivedExpression where Value == Int, Position == _PostgrestSelectOnly {
  /// `count()` — counts rows rather than values of a column.
  public static var countAll: Self {
    Self(embed: nil, inner: _PostgrestAggregateFunction.count.call)
  }
}

/// The five aggregate functions, each declared once and correct for a stored column, a JSON path
/// and either embed direction alike.
///
/// The result is **select position only**: PostgREST has no `HAVING`, and rejects an aggregate in
/// `order`, so filtering or ordering by one is a compile error. Grouping needs nothing declared —
/// selecting a plain column alongside an aggregate groups by it.
///
/// ## Selecting an aggregate
///
/// Declare it on a `@SelectionOf` property with `@Aggregate`, both from the `PostgrestMacros`
/// module:
///
/// ```swift
/// @SelectionOf(Order.self)
/// struct OrderTotals {
///   var category: String
///   @Aggregate(.sum, of: \Order.amount) var total: Double?
///   @Aggregate(.sum, of: \Order.tax) var taxTotal: Double?
///   @Aggregate(.count) var rows: Int
/// }
///
/// // select=category:category,total:amount.sum(),tax_total:tax.sum(),rows:count()
/// ```
///
/// The selection aliases each entry with its property name. Without the alias, PostgREST keys an
/// aggregate by the function name, so two `sum()`s in one select list would collide.
///
/// `@Aggregate` covers one function over one stored column. For anything else — a cast, a JSON
/// path, an aggregate through an embed, or a property typed other than the aggregate's result —
/// declare the expression on the relation's `Columns` and select it under a property of the same
/// name:
///
/// ```swift
/// extension Order.Columns {
///   var total: _PostgrestAggregate<Order, Double> { amount.sum() }
/// }
///
/// @SelectionOf(Order.self)
/// struct OrderTotal {
///   var total: Decimal?
/// }
/// ```
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
/// column's ``_PostgrestColumn`` does: an optional `Value` would strip the operators from anything
/// chained off it.
extension _PostgrestColumnExpression {
  private func aggregate<V>(
    _ function: _PostgrestAggregateFunction
  ) -> _PostgrestDerivedExpression<Root, V, _PostgrestSelectOnly> {
    _deriving(".\(function.call)")
  }

  /// The sum of this expression across the group, typed `Double` whatever the column's type.
  ///
  /// > Important: The wire value is a JSON integer, so past 2^53 a `Double` rounds it silently.
  /// > When a total can get that large, select it through a `Columns` member, which does not tie
  /// > the property to `Value`, and declare the property as `Int` or `Decimal`.
  public func sum() -> _PostgrestDerivedExpression<Root, Double, _PostgrestSelectOnly> {
    aggregate(.sum)
  }

  /// The mean of this expression across the group.
  public func avg() -> _PostgrestDerivedExpression<Root, Double, _PostgrestSelectOnly> {
    aggregate(.avg)
  }

  /// The smallest value of this expression in the group, keeping the expression's own type.
  public func min() -> _PostgrestDerivedExpression<Root, Value, _PostgrestSelectOnly> {
    aggregate(.min)
  }

  /// The largest value of this expression in the group.
  public func max() -> _PostgrestDerivedExpression<Root, Value, _PostgrestSelectOnly> {
    aggregate(.max)
  }

  /// How many non-null values of this expression are in the group.
  public func count() -> _PostgrestDerivedExpression<Root, Int, _PostgrestSelectOnly> {
    aggregate(.count)
  }
}
