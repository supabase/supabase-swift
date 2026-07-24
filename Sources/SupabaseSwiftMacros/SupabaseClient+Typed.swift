//
//  SupabaseClient+Typed.swift
//  SupabaseSwiftMacros
//
//  Created by Guilherme Souza on 25/06/25.
//

public import PostgREST
public import Supabase

extension SupabaseClient {
  /// Performs a typed query on a table.
  /// The table name and schema are taken from the type's `TableRepresentable` conformance.
  public func from<Table: TableRepresentable>(
    _ table: Table.Type
  ) -> TypedPostgrestQueryBuilder<Table> {
    let builder =
      Table.schema == "public"
      ? self.from(Table.tableName)
      : self.schema(Table.schema).from(Table.tableName)
    return TypedPostgrestQueryBuilder(underlying: builder)
  }

  /// Performs a typed query on a read-only table or view.
  public func from<Table: ReadOnlyTableRepresentable>(
    _ table: Table.Type
  ) -> TypedReadOnlyQueryBuilder<Table> {
    let builder =
      Table.schema == "public"
      ? self.from(Table.tableName)
      : self.schema(Table.schema).from(Table.tableName)
    return TypedReadOnlyQueryBuilder(underlying: builder)
  }
}
