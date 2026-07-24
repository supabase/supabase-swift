//
//  TypedPostgrestFilterBuilder.swift
//  PostgrestMacros
//
//  Created by Guilherme Souza on 24/06/25.
//

import Foundation
public import PostgREST

/// Wraps PostgrestFilterBuilder with typed KeyPath-based filter methods.
/// Table is constrained to ReadOnlyTableRepresentable (the shared base) so this builder
/// works for both read-write tables and views. Selection is the decoded return type.
public struct TypedPostgrestFilterBuilder<
  Table: ReadOnlyTableRepresentable,
  Selection: SelectionRepresentable
>: Sendable {
  let underlying: PostgrestFilterBuilder

  // MARK: - Comparison filters

  public func eq<V: PostgrestFilterValue>(
    _ column: KeyPath<Table, V>, value: V
  ) -> Self {
    _ = underlying.eq(Table.columnName(for: column), value: value)
    return self
  }

  public func neq<V: PostgrestFilterValue>(
    _ column: KeyPath<Table, V>, value: V
  ) -> Self {
    _ = underlying.neq(Table.columnName(for: column), value: value)
    return self
  }

  public func gt<V: PostgrestFilterValue>(
    _ column: KeyPath<Table, V>, value: V
  ) -> Self {
    _ = underlying.gt(Table.columnName(for: column), value: value)
    return self
  }

  public func gte<V: PostgrestFilterValue>(
    _ column: KeyPath<Table, V>, value: V
  ) -> Self {
    _ = underlying.gte(Table.columnName(for: column), value: value)
    return self
  }

  public func lt<V: PostgrestFilterValue>(
    _ column: KeyPath<Table, V>, value: V
  ) -> Self {
    _ = underlying.lt(Table.columnName(for: column), value: value)
    return self
  }

  public func lte<V: PostgrestFilterValue>(
    _ column: KeyPath<Table, V>, value: V
  ) -> Self {
    _ = underlying.lte(Table.columnName(for: column), value: value)
    return self
  }

  public func `in`<V: PostgrestFilterValue>(
    _ column: KeyPath<Table, V>, values: [V]
  ) -> Self {
    _ = underlying.in(Table.columnName(for: column), values: values)
    return self
  }

  public func like<V>(
    _ column: KeyPath<Table, V>, pattern: String
  ) -> Self {
    _ = underlying.like(Table.columnName(for: column), pattern: pattern)
    return self
  }

  public func ilike<V>(
    _ column: KeyPath<Table, V>, pattern: String
  ) -> Self {
    _ = underlying.ilike(Table.columnName(for: column), pattern: pattern)
    return self
  }

  public func `is`<V>(
    _ column: KeyPath<Table, V?>, value: Bool?
  ) -> Self {
    _ = underlying.is(Table.columnName(for: column), value: value)
    return self
  }

  // MARK: - String escape hatch (complex OR, raw PostgREST expressions)

  public func filter(_ column: String, operator op: String, value: String) -> Self {
    _ = underlying.filter(column, operator: op, value: value)
    return self
  }

  public func or(_ filters: String, referencedTable: String? = nil) -> Self {
    _ = underlying.or(filters, referencedTable: referencedTable)
    return self
  }

  // MARK: - Transforms

  public func order<V>(
    _ column: KeyPath<Table, V>,
    ascending: Bool = true,
    nullsFirst: Bool = false,
    referencedTable: String? = nil
  ) -> TypedPostgrestTransformBuilder<Table, Selection> {
    _ = underlying.order(
      Table.columnName(for: column),
      ascending: ascending,
      nullsFirst: nullsFirst,
      referencedTable: referencedTable
    )
    return TypedPostgrestTransformBuilder(underlying: underlying)
  }

  public func limit(
    _ count: Int, referencedTable: String? = nil
  ) -> TypedPostgrestTransformBuilder<Table, Selection> {
    _ = underlying.limit(count, referencedTable: referencedTable)
    return TypedPostgrestTransformBuilder(underlying: underlying)
  }

  public func range(
    from: Int, to: Int, referencedTable: String? = nil
  ) -> TypedPostgrestTransformBuilder<Table, Selection> {
    _ = underlying.range(from: from, to: to, referencedTable: referencedTable)
    return TypedPostgrestTransformBuilder(underlying: underlying)
  }

  public func single() -> TypedSingleResultBuilder<Table, Selection> {
    TypedSingleResultBuilder(underlying: underlying.single())
  }

  // MARK: - Execute

  public func execute() async throws -> PostgrestResponse<[Selection]> {
    try await underlying.execute()
  }
}
