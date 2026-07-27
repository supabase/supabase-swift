import Foundation

/// Conformance synthesized by @SelectionOf or @Table.
/// Carries the PostgREST column select expression and is Decodable.
public protocol SelectionRepresentable: Decodable {
  static var selectString: String { get }
}

/// Conformance synthesized by @Table(readOnly: true) — for views.
/// Shared base for both read-only and read-write tables so that
/// TypedPostgrestFilterBuilder can be constrained to this single protocol.
public protocol ReadOnlyTableRepresentable: SelectionRepresentable {
  static var tableName: String { get }
  static var schema: String { get }
  static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String
}

/// Conformance synthesized by @Table on a read-write table.
/// Refines ReadOnlyTableRepresentable by adding Insert and Update associated types.
/// TypedPostgrestQueryBuilder<Table: TableRepresentable> exposes insert/update/delete.
public protocol TableRepresentable: ReadOnlyTableRepresentable {
  associatedtype Insert: Encodable
  associatedtype Update: Encodable
}
