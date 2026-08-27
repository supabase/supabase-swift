//
//  PostgrestFilter+Comparison.swift
//  PostgREST
//
//  Created by Guilherme Souza on 26/08/26.
//

extension PostgrestFilterableExpression where Value: PostgrestFilterValue {
  /// Matches rows where this column equals `value`.
  ///
  /// `nil` is not accepted; use ``PostgrestNullableColumn/isNull()`` to test for SQL `NULL`.
  public func eq(_ value: Value) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: "eq", value: value.rawValue)
  }

  /// Matches rows where this column is not equal to `value`.
  public func neq(_ value: Value) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: "neq", value: value.rawValue)
  }

  /// Matches rows where this column is greater than `value`.
  public func gt(_ value: Value) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: "gt", value: value.rawValue)
  }

  /// Matches rows where this column is greater than or equal to `value`.
  public func gte(_ value: Value) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: "gte", value: value.rawValue)
  }

  /// Matches rows where this column is less than `value`.
  public func lt(_ value: Value) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: "lt", value: value.rawValue)
  }

  /// Matches rows where this column is less than or equal to `value`.
  public func lte(_ value: Value) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: "lte", value: value.rawValue)
  }

  /// Matches rows where this column is distinct from `value`.
  ///
  /// Unlike ``neq(_:)``, a `NULL` row matches any non-null operand.
  public func isDistinct(_ value: Value) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: "isdistinct", value: value.rawValue)
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
    PostgrestFilter(column: postgrestExpression, operator: "is", value: "true")
  }

  /// Matches rows where this boolean column IS false.
  public func isFalse() -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: "is", value: "false")
  }
}

// MARK: - Null checks

extension PostgrestNullableColumn {
  /// Matches rows where this column is SQL `NULL`.
  ///
  /// There is no `isNotNull()` — negate instead: `!$0.dueDate.isNull()` renders
  /// `due_at=not.is.null`.
  public func isNull() -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: "is", value: "null")
  }
}
