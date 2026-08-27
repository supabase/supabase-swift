//
//  PostgrestFilter+Pattern.swift
//  PostgREST
//
//  Created by Guilherme Souza on 26/08/26.
//

extension PostgrestFilter {
  /// `(a,b,c)` — the parenthesised form `in` takes.
  ///
  /// Must use the filter escaper, not the array one: they reserve different characters, and an
  /// `in.(…)` list is filter-value syntax. With the array escaper, `name=in.(p(q),Ada)` answers
  /// 200 with zero rows.
  static func list(_ values: [some PostgrestFilterValue]) -> String {
    "(\(values.map { escapePostgRESTFilterValue($0.rawValue) }.joined(separator: ",")))"
  }

  /// `{a,b}` — the braced form the multi-pattern operators take.
  ///
  /// Array-literal syntax, so members need the array escaper: a raw join splits any pattern
  /// containing a comma into two, and a stray `{`/`}` corrupts the literal's delimiters.
  static func braced(_ patterns: [String]) -> String {
    "{\(patterns.map(escapePostgRESTArrayLiteralElement).joined(separator: ","))}"
  }
}

extension PostgrestFilterableExpression where Value == String {
  /// Matches rows where this column matches the `LIKE` `pattern`, case-sensitively.
  ///
  /// `%` matches any run of characters, `_` matches exactly one.
  public func like(_ pattern: String) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: "like", value: pattern)
  }

  /// Matches rows where this column matches the `LIKE` `pattern`, case-insensitively.
  public func ilike(_ pattern: String) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: "ilike", value: pattern)
  }

  /// Matches rows where this column matches the POSIX regular expression `pattern`,
  /// case-sensitively.
  ///
  /// Named `regexMatch`, not `match`: across Supabase SDKs `match` means a multi-column equality
  /// shorthand.
  public func regexMatch(_ pattern: String) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: "match", value: pattern)
  }

  /// Matches rows where this column matches the POSIX regular expression `pattern`,
  /// case-insensitively.
  public func regexIMatch(_ pattern: String) -> PostgrestFilter<Root> {
    PostgrestFilter(column: postgrestExpression, operator: "imatch", value: pattern)
  }

  /// Matches rows where this column matches every one of `patterns`, case-sensitively.
  ///
  /// An empty `patterns` matches no rows — PostgREST accepts `like(all).{}` without error.
  public func likeAllOf(_ patterns: [String]) -> PostgrestFilter<Root> {
    PostgrestFilter(
      column: postgrestExpression, operator: "like(all)",
      value: PostgrestFilter<Root>.braced(patterns))
  }

  /// Matches rows where this column matches at least one of `patterns`, case-sensitively.
  ///
  /// An empty `patterns` matches no rows.
  public func likeAnyOf(_ patterns: [String]) -> PostgrestFilter<Root> {
    PostgrestFilter(
      column: postgrestExpression, operator: "like(any)",
      value: PostgrestFilter<Root>.braced(patterns))
  }

  /// Matches rows where this column matches every one of `patterns`, case-insensitively.
  ///
  /// An empty `patterns` matches no rows.
  public func ilikeAllOf(_ patterns: [String]) -> PostgrestFilter<Root> {
    PostgrestFilter(
      column: postgrestExpression, operator: "ilike(all)",
      value: PostgrestFilter<Root>.braced(patterns))
  }

  /// Matches rows where this column matches at least one of `patterns`, case-insensitively.
  ///
  /// An empty `patterns` matches no rows.
  public func ilikeAnyOf(_ patterns: [String]) -> PostgrestFilter<Root> {
    PostgrestFilter(
      column: postgrestExpression, operator: "ilike(any)",
      value: PostgrestFilter<Root>.braced(patterns))
  }
}

extension PostgrestFilterableExpression where Value: PostgrestFilterValue {
  /// Matches rows where this column is one of `values`.
  ///
  /// There is no `notIn` — negate instead: `!$0.id.in([1, 2])` renders `id=not.in.(1,2)`.
  ///
  /// An empty `values` matches no rows.
  ///
  /// Built as a raw node so `group()` leaves the operand alone: `in.(…)`'s parens belong to the
  /// operator's grammar, and re-quoting them gives `or=(id.in."(2,3)",…)`, a `PGRST100`. Members
  /// are still escaped, by `list(_:)`. This applies to `in.(…)` alone — a range literal is the
  /// opposite case and needs that escaping to survive a group.
  public func `in`(_ values: [Value]) -> PostgrestFilter<Root> {
    PostgrestFilter(
      rawColumn: postgrestExpression, operand: "in.\(PostgrestFilter<Root>.list(values))")
  }
}
