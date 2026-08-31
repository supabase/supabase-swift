//
//  PostgrestFilter+Comparison.swift
//  PostgREST
//
//  Created by Guilherme Souza on 26/08/26.
//

extension PostgrestFilterableExpression where Value: PostgrestFilterValue {
  /// Matches rows where this column equals `value`.
  ///
  /// `nil` is not accepted; use ``PostgrestNullableExpression/isNull()`` to test for SQL `NULL`.
  public func eq(_ value: Value) -> PostgrestFilter<Root> {
    PostgrestFilter(
      column: postgrestExpression, operator: PostgrestOperator.eq.rawValue, value: value.rawValue)
  }

  /// Matches rows where this column is not equal to `value`.
  public func neq(_ value: Value) -> PostgrestFilter<Root> {
    PostgrestFilter(
      column: postgrestExpression, operator: PostgrestOperator.neq.rawValue, value: value.rawValue)
  }

  /// Matches rows where this column is greater than `value`.
  public func gt(_ value: Value) -> PostgrestFilter<Root> {
    PostgrestFilter(
      column: postgrestExpression, operator: PostgrestOperator.gt.rawValue, value: value.rawValue)
  }

  /// Matches rows where this column is greater than or equal to `value`.
  public func gte(_ value: Value) -> PostgrestFilter<Root> {
    PostgrestFilter(
      column: postgrestExpression, operator: PostgrestOperator.gte.rawValue, value: value.rawValue)
  }

  /// Matches rows where this column is less than `value`.
  public func lt(_ value: Value) -> PostgrestFilter<Root> {
    PostgrestFilter(
      column: postgrestExpression, operator: PostgrestOperator.lt.rawValue, value: value.rawValue)
  }

  /// Matches rows where this column is less than or equal to `value`.
  public func lte(_ value: Value) -> PostgrestFilter<Root> {
    PostgrestFilter(
      column: postgrestExpression, operator: PostgrestOperator.lte.rawValue, value: value.rawValue)
  }

  /// Matches rows where this column is distinct from `value`.
  ///
  /// Unlike ``neq(_:)``, a `NULL` row matches any non-null operand.
  public func isDistinct(_ value: Value) -> PostgrestFilter<Root> {
    PostgrestFilter(
      column: postgrestExpression, operator: PostgrestOperator.isdistinct.rawValue,
      value: value.rawValue)
  }
}

// MARK: - Escape hatch

extension PostgrestFilterableExpression {
  /// Applies an operator this SDK has no member for — a PostgREST operator newer than this
  /// version, for instance. The column stays compiler-checked.
  ///
  /// ```swift
  /// .where { $0.tags.raw("someop.value") }   // tags=someop.value
  /// ```
  ///
  /// Composes like any other filter: `!$0.tags.raw("someop.v")` renders `tags=not.someop.v`.
  ///
  /// > Important: The operand reaches the server unescaped, so if it is not valid in the
  /// > `or=(…)` grammar, keep the filter out of every subtree beneath `||` or `!` — not just out
  /// > of their immediate operands. Anything below one of those is rendered in that stricter
  /// > grammar however deep it sits, so `($0.a.eq(1) && $0.tags.raw("someop.v")) || $0.b.eq(2)`
  /// > routes the raw operand through it despite the immediate combinator being `&&`. See
  /// > ``PostgrestFilter/raw(_:_:)``.
  ///
  /// - Parameter operand: Everything after the `=`, for example `"eq.10"`.
  public func raw(_ operand: String) -> PostgrestFilter<Root> {
    PostgrestFilter(rawColumn: postgrestExpression, operand: operand)
  }
}

// MARK: - Boolean IS checks

extension PostgrestFilterableExpression where Value == Bool {
  /// Matches rows where this boolean column IS true.
  ///
  /// On a nullable column this differs from `eq(true)`: `eq.true` is unknown for a `NULL` row,
  /// `is.true` is false.
  public func isTrue() -> PostgrestFilter<Root> {
    PostgrestFilter(
      column: postgrestExpression, operator: PostgrestOperator.`is`.rawValue, value: "true")
  }

  /// Matches rows where this boolean column IS false.
  public func isFalse() -> PostgrestFilter<Root> {
    PostgrestFilter(
      column: postgrestExpression, operator: PostgrestOperator.`is`.rawValue, value: "false")
  }
}

// MARK: - Null checks

extension PostgrestNullableExpression {
  /// Matches rows where this expression is SQL `NULL`.
  ///
  /// There is no `isNotNull()` — negate instead: `!$0.dueDate.isNull()` renders
  /// `due_at=not.is.null`.
  public func isNull() -> PostgrestFilter<Root> {
    PostgrestFilter(
      column: postgrestExpression, operator: PostgrestOperator.`is`.rawValue, value: "null")
  }
}
