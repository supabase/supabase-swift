//
//  PostgrestClient+Typed.swift
//  PostgREST
//
//  Created by Guilherme Souza on 24/06/25.
//

import Foundation
import HTTPTypes
import SupabaseSwiftMacros

extension PostgrestClient {
  /// Perform a typed query on a table represented by a `TableRepresentable` type.
  ///
  /// - Parameter table: The table type to query. Must conform to `TableRepresentable`.
  /// - Returns: A `TypedPostgrestQueryBuilder` for building the query.
  public func from<Table: TableRepresentable>(
    _ table: Table.Type
  ) -> TypedPostgrestQueryBuilder<Table> {
    let tableSchema = table.schema == "public" ? nil : table.schema
    var config = configuration
    if let tableSchema {
      config.schema = tableSchema
    }
    let queryBuilder = PostgrestQueryBuilder(
      configuration: config,
      request: .init(
        url: config.url.appendingPathComponent(table.tableName),
        method: .get,
        headers: HTTPFields(config.headers)
      )
    )
    return TypedPostgrestQueryBuilder(underlying: queryBuilder)
  }

  /// Perform a typed query on a read-only table (view) represented by a `ReadOnlyTableRepresentable` type.
  ///
  /// - Parameter table: The view type to query. Must conform to `ReadOnlyTableRepresentable` but NOT `TableRepresentable`.
  /// - Returns: A `TypedReadOnlyQueryBuilder` for building the query.
  public func from<Table: ReadOnlyTableRepresentable>(
    _ table: Table.Type
  ) -> TypedReadOnlyQueryBuilder<Table> {
    let tableSchema = table.schema == "public" ? nil : table.schema
    var config = configuration
    if let tableSchema {
      config.schema = tableSchema
    }
    let queryBuilder = PostgrestQueryBuilder(
      configuration: config,
      request: .init(
        url: config.url.appendingPathComponent(table.tableName),
        method: .get,
        headers: HTTPFields(config.headers)
      )
    )
    return TypedReadOnlyQueryBuilder(underlying: queryBuilder)
  }
}
