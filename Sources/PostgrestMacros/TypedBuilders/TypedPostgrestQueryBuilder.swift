//
//  TypedPostgrestQueryBuilder.swift
//  PostgrestMacros
//
//  Created by Guilherme Souza on 24/06/25.
//

import Foundation
public import PostgREST

/// Entry point returned by PostgrestClient.from(_ table: T.Type).
/// Mirrors PostgrestQueryBuilder with typed Insert/Update/Delete operations.
public struct TypedPostgrestQueryBuilder<Table: TableRepresentable>: Sendable {
  let underlying: PostgrestQueryBuilder

  // MARK: - SELECT

  /// Selects all columns, returning [Table] (the full row type).
  public func select(
    head: Bool = false,
    count: CountOption? = nil
  ) -> TypedPostgrestFilterBuilder<Table, Table> {
    TypedPostgrestFilterBuilder(
      underlying: underlying.select(Table.selectString, head: head, count: count)
    )
  }

  /// Selects only the columns defined by Selection, returning [Selection].
  public func select<S: SelectionRepresentable>(
    _ selection: S.Type,
    head: Bool = false,
    count: CountOption? = nil
  ) -> TypedPostgrestFilterBuilder<Table, S> {
    TypedPostgrestFilterBuilder(
      underlying: underlying.select(S.selectString, head: head, count: count)
    )
  }

  // MARK: - INSERT

  public func insert(
    _ value: Table.Insert,
    returning: PostgrestReturningOptions? = nil,
    count: CountOption? = nil
  ) throws -> PostgrestTransformBuilder {
    try underlying.insert(value, returning: returning, count: count)
  }

  public func insert(
    _ values: [Table.Insert],
    returning: PostgrestReturningOptions? = nil,
    count: CountOption? = nil
  ) throws -> PostgrestTransformBuilder {
    try underlying.insert(values, returning: returning, count: count)
  }

  // MARK: - UPSERT

  public func upsert(
    _ value: Table.Insert,
    onConflict: String? = nil,
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil,
    ignoreDuplicates: Bool = false
  ) throws -> PostgrestTransformBuilder {
    try underlying.upsert(
      value,
      onConflict: onConflict,
      returning: returning,
      count: count,
      ignoreDuplicates: ignoreDuplicates
    )
  }

  // MARK: - UPDATE

  public func update(
    _ value: Table.Update,
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil
  ) throws -> TypedPostgrestFilterBuilder<Table, Table> {
    TypedPostgrestFilterBuilder(
      underlying: try underlying.update(value, returning: returning, count: count)
    )
  }

  // MARK: - DELETE

  public func delete(
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil
  ) -> TypedPostgrestFilterBuilder<Table, Table> {
    TypedPostgrestFilterBuilder(
      underlying: underlying.delete(returning: returning, count: count)
    )
  }
}

/// Entry point for read-only tables (views). Only select is available.
/// TypedPostgrestFilterBuilder is constrained to ReadOnlyTableRepresentable so this compiles
/// without requiring Table to also conform to TableRepresentable.
public struct TypedReadOnlyQueryBuilder<Table: ReadOnlyTableRepresentable>: Sendable {
  let underlying: PostgrestQueryBuilder

  public func select(
    head: Bool = false,
    count: CountOption? = nil
  ) -> TypedPostgrestFilterBuilder<Table, Table> {
    TypedPostgrestFilterBuilder(
      underlying: underlying.select(Table.selectString, head: head, count: count)
    )
  }

  public func select<S: SelectionRepresentable>(
    _ selection: S.Type,
    head: Bool = false,
    count: CountOption? = nil
  ) -> TypedPostgrestFilterBuilder<Table, S> {
    TypedPostgrestFilterBuilder(
      underlying: underlying.select(S.selectString, head: head, count: count)
    )
  }
}
