//
//  PostgrestClient+Typed.swift
//  SupabaseSwiftMacros
//
//  Created by Guilherme Souza on 24/06/25.
//

public import PostgREST

extension PostgrestClient {
  /// Returns a typed query builder for the given table.
  /// The table name and schema are taken from the type's TableRepresentable conformance.
  public func from<Table: TableRepresentable>(
    _ table: Table.Type
  ) -> TypedPostgrestQueryBuilder<Table> {
    let client = Table.schema == "public" ? self : self.schema(Table.schema)
    return TypedPostgrestQueryBuilder(underlying: client.from(Table.tableName))
  }

  /// Returns a read-only typed query builder for a view.
  public func from<Table: ReadOnlyTableRepresentable>(
    _ table: Table.Type
  ) -> TypedReadOnlyQueryBuilder<Table> {
    let client = Table.schema == "public" ? self : self.schema(Table.schema)
    return TypedReadOnlyQueryBuilder(underlying: client.from(Table.tableName))
  }
}
