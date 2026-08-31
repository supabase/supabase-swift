//
//  PostgrestDerivedExpression.swift
//  PostgREST
//
//  Created by Guilherme Souza on 27/08/26.
//

/// A cast, JSON path or aggregate applied to another expression.
///
/// One type for all of them, replacing `PostgrestCastColumn`, `PostgrestJSONPath`,
/// `PostgrestAggregate` and `PostgrestToOneDerivedColumn`. It keeps the embed name and the inner
/// expression apart, so a further derivation lands inside the embed's parentheses:
/// `Order.columns.todo.amount.sum().cast(to: .text)` renders `todo(amount.sum()::text)`, with the
/// cast applied — the flattened form returns the value uncast.
///
/// `Position` is inherited from whatever the derivation was applied to, so a JSON path on a
/// to-many embed is select-only without that rule being restated per embed kind.
public struct PostgrestDerivedExpression<
  Root: PostgrestRelation,
  Value,
  Position: PostgrestPosition
>: PostgrestColumnExpression {
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
  public func _deriving<V, P: PostgrestPosition>(
    _ derivation: String
  ) -> PostgrestDerivedExpression<Root, V, P> {
    PostgrestDerivedExpression<Root, V, P>(embed: embed, inner: inner + derivation)
  }
}

extension PostgrestDerivedExpression: PostgrestFilterableExpression
where Position: PostgrestFilterablePosition {}

extension PostgrestDerivedExpression: PostgrestOrderableExpression
where Position: PostgrestOrderablePosition {}

/// A cast is select position only, whatever it was applied to.
public typealias PostgrestCastColumn<Root: PostgrestRelation, Value> =
  PostgrestDerivedExpression<Root, Value, PostgrestSelectOnly>

/// An aggregate is select position only, whatever it was applied to.
public typealias PostgrestAggregate<Root: PostgrestRelation, Value> =
  PostgrestDerivedExpression<Root, Value, PostgrestSelectOnly>
