//
//  TableRepresentable.swift
//  PostgREST
//
//  Created by Guilherme Souza on 24/06/25.
//

import Foundation

/// Conformance synthesized by `@SelectionOf` or `@Table`.
/// Carries the PostgREST column select expression and is `Decodable`.
public protocol SelectionRepresentable: Decodable {
  static var selectString: String { get }
}

/// Conformance synthesized by `@Table(readOnly: true)` — for views.
/// Shared base for both read-only and read-write tables so that the generic
/// filter/transform builders can be constrained to this single protocol.
public protocol ReadOnlyTableRepresentable: SelectionRepresentable {
  static var tableName: String { get }
  static var schema: String { get }
  static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String
}

/// Conformance synthesized by `@Table` on a read-write table.
/// Refines ``ReadOnlyTableRepresentable`` by adding `Insert` and `Update` associated types,
/// which gate the typed `insert`/`update`/`upsert` methods on the query builder.
public protocol TableRepresentable: ReadOnlyTableRepresentable {
  associatedtype Insert: Encodable
  associatedtype Update: Encodable
}

/// Sentinel type used for the untyped builder specializations
/// (``PostgrestQueryBuilder``, ``PostgrestFilterBuilder``, ``PostgrestTransformBuilder``).
///
/// `AnyTable` deliberately conforms to none of the builder protocols. As a result every
/// KeyPath- and associated-type-based typed method (`eq(_:value:)` on a `KeyPath`,
/// `insert(_ value: Table.Insert)`, …) becomes uncallable when `Table == AnyTable` — you
/// cannot construct a `KeyPath<AnyTable, V>` and there is no `AnyTable.Insert`. The
/// String-based API stays available unconditionally on every specialization.
public enum AnyTable {}
