//
//  PostgrestFilter+ComparisonOperators.swift
//  PostgREST
//
//  Created by Guilherme Souza on 09/10/26.
//

// Each operator calls the method of the same meaning, so both spellings build the same tree.

/// Matches rows where `lhs` equals `rhs`. Same as `lhs.eq(rhs)`.
public func == <E: _PostgrestFilterableExpression>(
  lhs: E, rhs: E.Value
) -> _PostgrestFilter<E.Root> where E.Value: PostgrestFilterValue {
  lhs.eq(rhs)
}

/// Matches rows where `lhs` is not equal to `rhs`. Same as `lhs.neq(rhs)`.
public func != <E: _PostgrestFilterableExpression>(
  lhs: E, rhs: E.Value
) -> _PostgrestFilter<E.Root> where E.Value: PostgrestFilterValue {
  lhs.neq(rhs)
}

/// Matches rows where `lhs` is less than `rhs`. Same as `lhs.lt(rhs)`.
public func < <E: _PostgrestFilterableExpression>(
  lhs: E, rhs: E.Value
) -> _PostgrestFilter<E.Root> where E.Value: PostgrestFilterValue {
  lhs.lt(rhs)
}

/// Matches rows where `lhs` is less than or equal to `rhs`. Same as `lhs.lte(rhs)`.
public func <= <E: _PostgrestFilterableExpression>(
  lhs: E, rhs: E.Value
) -> _PostgrestFilter<E.Root> where E.Value: PostgrestFilterValue {
  lhs.lte(rhs)
}

/// Matches rows where `lhs` is greater than `rhs`. Same as `lhs.gt(rhs)`.
public func > <E: _PostgrestFilterableExpression>(
  lhs: E, rhs: E.Value
) -> _PostgrestFilter<E.Root> where E.Value: PostgrestFilterValue {
  lhs.gt(rhs)
}

/// Matches rows where `lhs` is greater than or equal to `rhs`. Same as `lhs.gte(rhs)`.
public func >= <E: _PostgrestFilterableExpression>(
  lhs: E, rhs: E.Value
) -> _PostgrestFilter<E.Root> where E.Value: PostgrestFilterValue {
  lhs.gte(rhs)
}

/// Matches rows where `lhs` is SQL `NULL`. Same as `lhs.isNull()`.
///
/// Renders `is.null`, never `eq.null`: on a `text` column `eq.null` matches the string `'null'`.
public func == <E: _PostgrestNullableExpression>(
  lhs: E, rhs: _OptionalNilComparisonType
) -> _PostgrestFilter<E.Root> {
  lhs.isNull()
}

/// Matches rows where `lhs` is not SQL `NULL`. Same as `!lhs.isNull()`.
public func != <E: _PostgrestNullableExpression>(
  lhs: E, rhs: _OptionalNilComparisonType
) -> _PostgrestFilter<E.Root> {
  !lhs.isNull()
}
