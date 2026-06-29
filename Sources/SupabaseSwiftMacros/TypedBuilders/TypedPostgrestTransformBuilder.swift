//
//  TypedPostgrestTransformBuilder.swift
//  SupabaseSwiftMacros
//
//  Created by Guilherme Souza on 24/06/25.
//

import Foundation
import PostgREST

/// Wraps PostgrestTransformBuilder with typed column ordering.
public struct TypedPostgrestTransformBuilder<
  Table: ReadOnlyTableRepresentable,
  Selection: SelectionRepresentable
>: Sendable {
  let underlying: PostgrestTransformBuilder

  /// Orders results by the given column KeyPath.
  public func order<V>(
    _ column: KeyPath<Table, V>,
    ascending: Bool = true,
    nullsFirst: Bool = false,
    referencedTable: String? = nil
  ) -> Self {
    _ = underlying.order(
      Table.columnName(for: column),
      ascending: ascending,
      nullsFirst: nullsFirst,
      referencedTable: referencedTable
    )
    return self
  }

  public func limit(_ count: Int, referencedTable: String? = nil) -> Self {
    _ = underlying.limit(count, referencedTable: referencedTable)
    return self
  }

  public func range(from: Int, to: Int, referencedTable: String? = nil) -> Self {
    _ = underlying.range(from: from, to: to, referencedTable: referencedTable)
    return self
  }

  public func single() -> TypedSingleResultBuilder<Table, Selection> {
    TypedSingleResultBuilder(underlying: underlying.single())
  }

  public func execute() async throws -> PostgrestResponse<[Selection]> {
    try await underlying.execute()
  }
}
