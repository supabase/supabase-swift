//
//  PostgrestFilter+Pattern.swift
//  PostgREST
//
//  Created by Guilherme Souza on 26/08/26.
//

extension PostgrestFilterableExpression where Value == String {
  /// Matches rows where this column matches the `LIKE` `pattern`, case-sensitively.
  ///
  /// `%` matches any run of characters, `_` matches exactly one.
  public func like(_ pattern: String) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: .like, value: pattern)
  }

  /// Matches rows where this column matches the `LIKE` `pattern`, case-insensitively.
  public func ilike(_ pattern: String) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: .ilike, value: pattern)
  }

  /// Matches rows where this column matches the POSIX regular expression `pattern`,
  /// case-sensitively.
  ///
  /// Named `regexMatch`, not `match`: across Supabase SDKs `match` means a multi-column equality
  /// shorthand.
  public func regexMatch(_ pattern: String) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: .regexMatch, value: pattern)
  }

  /// Matches rows where this column matches the POSIX regular expression `pattern`,
  /// case-insensitively.
  public func regexIMatch(_ pattern: String) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: .regexIMatch, value: pattern)
  }

  /// Matches rows where this column matches every one of `patterns`, case-sensitively.
  ///
  /// An empty `patterns` matches **every** row, including rows where the column is `NULL`:
  /// PostgREST renders this as `LIKE ALL('{}')`, and a quantified `ALL` over an empty array is
  /// vacuously true. `likeAnyOf`/`ilikeAnyOf` are the reverse — empty matches no rows.
  public func likeAllOf(_ patterns: [String]) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: .likeAllOf, value: patterns)
  }

  /// Matches rows where this column matches at least one of `patterns`, case-sensitively.
  ///
  /// An empty `patterns` matches no rows.
  public func likeAnyOf(_ patterns: [String]) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: .likeAnyOf, value: patterns)
  }

  /// Matches rows where this column matches every one of `patterns`, case-insensitively.
  ///
  /// An empty `patterns` matches **every** row, including rows where the column is `NULL`:
  /// PostgREST renders this as `ILIKE ALL('{}')`, and a quantified `ALL` over an empty array is
  /// vacuously true. `likeAnyOf`/`ilikeAnyOf` are the reverse — empty matches no rows.
  public func ilikeAllOf(_ patterns: [String]) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: .ilikeAllOf, value: patterns)
  }

  /// Matches rows where this column matches at least one of `patterns`, case-insensitively.
  ///
  /// An empty `patterns` matches no rows.
  public func ilikeAnyOf(_ patterns: [String]) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: .ilikeAnyOf, value: patterns)
  }
}

extension PostgrestFilterableExpression where Value: PostgrestFilterValue {
  /// Matches rows where this column is one of `values`.
  ///
  /// There is no `notIn` — negate instead: `!$0.id.in([1, 2])` renders `id=not.in.(1,2)`.
  ///
  /// An empty `values` matches no rows.
  public func `in`(_ values: [Value]) -> PostgrestFilter<Root> {
    PostgrestFilter(
      column: postgrestExpression, operator: .in, operand: .list(values.map(\.rawValue)))
  }
}
