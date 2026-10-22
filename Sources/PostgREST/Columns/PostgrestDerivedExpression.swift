//
//  PostgrestDerivedExpression.swift
//  PostgREST
//
//  Created by Guilherme Souza on 27/08/26.
//

/// A cast, JSON path or aggregate applied to another expression.
///
/// One type for all of them, replacing `_PostgrestCastColumn`, `PostgrestJSONPath`,
/// `_PostgrestAggregate` and `PostgrestToOneDerivedColumn`. It keeps the embed name and the inner
/// expression apart, so a further derivation lands inside the embed's parentheses:
/// `Order.columns.todo.amount.sum().cast(to: .text)` renders `todo(amount.sum()::text)`, with the
/// cast applied — the flattened form returns the value uncast.
///
/// `Position` is inherited from whatever the derivation was applied to, so a JSON path on a
/// to-many embed is select-only without that rule being restated per embed kind.
public struct _PostgrestDerivedExpression<
  Root: _PostgrestRelation,
  Value,
  Position: _PostgrestPosition
>: _PostgrestColumnExpression {
  let embed: String?
  let inner: String

  init(embed: String?, inner: String) {
    self.embed = embed
    self.inner = inner
  }

  public var postgrestExpression: String {
    embed.map { "\($0)(\(inner))" } ?? inner
  }

  /// Keeps the embed, so a chained derivation stays inside the parentheses.
  public func _deriving<V, P: _PostgrestPosition>(
    _ derivation: String
  ) -> _PostgrestDerivedExpression<Root, V, P> {
    _PostgrestDerivedExpression<Root, V, P>(embed: embed, inner: inner + derivation)
  }
}

extension _PostgrestDerivedExpression: _PostgrestFilterableExpression
where Position: _PostgrestFilterablePosition {}

extension _PostgrestDerivedExpression: _PostgrestOrderableExpression
where Position: _PostgrestOrderablePosition {}

/// A JSON extraction can be `NULL` whatever the column's own nullability — `data->>'name'` is
/// `NULL` when the key is absent, even on a `NOT NULL` `jsonb` column — so it gets `isNull()`
/// without the column having to be nullable.
///
/// Keyed on the filterable position rather than named per accessor: a cast and an aggregate are
/// select-only, so neither picks the operator up, and a JSON path inherits its receiver's position.
extension _PostgrestDerivedExpression: _PostgrestNullableExpression
where Position: _PostgrestFilterablePosition {}

/// A cast is select position only, whatever it was applied to.
public typealias _PostgrestCastColumn<Root: _PostgrestRelation, Value> =
  _PostgrestDerivedExpression<Root, Value, _PostgrestSelectOnly>

/// An aggregate is select position only, whatever it was applied to.
public typealias _PostgrestAggregate<Root: _PostgrestRelation, Value> =
  _PostgrestDerivedExpression<Root, Value, _PostgrestSelectOnly>
