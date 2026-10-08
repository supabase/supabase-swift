//
//  PostgresChange.swift
//  Realtime
//
//  Created by Guilherme Souza on 08/10/26.
//

package import ConcurrencyExtras
public import Foundation

/// A row change the server read from the Postgres write-ahead log.
public struct PostgresChange: Sendable {
  /// The DML statement that made the change.
  public enum Kind: Sendable, Hashable {
    /// A row was inserted.
    case insert
    /// A row was updated.
    case update
    /// A row was deleted.
    case delete
  }

  /// The statement that made the change.
  public var kind: Kind
  /// The schema of the changed table.
  public var schema: String
  /// The changed table.
  public var table: String
  /// When the transaction committed.
  public var commitTimestamp: Date
  /// The table's columns, with their Postgres type names.
  public var columns: [PostgresColumn]
  /// The row after the change. `nil` for a delete.
  public var record: PostgresRow?
  /// The row before the change. `nil` for an insert. Without `REPLICA IDENTITY FULL`, or under
  /// row level security, it holds only the primary key columns.
  public var oldRecord: PostgresRow?
  /// Errors the server reports for this change, such as `"Error 401: Unauthorized"` when row
  /// level security hides the row from the subscriber.
  public var errors: [String]

  /// Reads the `data` object of a `postgres_changes` message.
  package init(payload: JSONObject) throws {
    let type = payload["type"]?.stringValue
    switch type {
    case "INSERT": kind = .insert
    case "UPDATE": kind = .update
    case "DELETE": kind = .delete
    default:
      throw RealtimeError.decoding("unknown postgres change type \(type ?? "nil")")
    }
    guard let schema = payload["schema"]?.stringValue, let table = payload["table"]?.stringValue
    else {
      throw RealtimeError.decoding("postgres change without a schema or table")
    }
    guard let timestamp = payload["commit_timestamp"]?.stringValue, let date = timestamp.date else {
      throw RealtimeError.decoding("postgres change without a valid commit_timestamp")
    }
    self.schema = schema
    self.table = table
    commitTimestamp = date
    columns = (payload["columns"]?.arrayValue ?? []).compactMap { column in
      guard let name = column.objectValue?["name"]?.stringValue,
        let type = column.objectValue?["type"]?.stringValue
      else { return nil }
      return PostgresColumn(name: name, type: type)
    }
    record = payload["record"]?.objectValue.map(PostgresRow.init(values:))
    oldRecord = payload["old_record"]?.objectValue.map(PostgresRow.init(values:))
    errors = payload["errors"]?.arrayValue?.compactMap(\.stringValue) ?? []
  }
}

/// A column of the changed table.
public struct PostgresColumn: Sendable, Hashable {
  /// The column name.
  public var name: String
  /// The Postgres type name, such as `"int8"` or `"timestamptz"`.
  public var type: String
}

/// A row of a ``PostgresChange``, as the JSON the server sent.
public struct PostgresRow: Sendable, Hashable {
  /// The column values, by column name.
  public var values: JSONObject

  /// The value of `column`, or `nil` when the row does not have it.
  public subscript(column: String) -> JSONValue? {
    values[column]
  }

  /// Decodes the row as `T`.
  ///
  /// - Throws: ``RealtimeError`` of kind ``RealtimeError/Kind/decoding`` when the row does not
  ///   decode.
  public func decode<T: Decodable>(
    as _: T.Type = T.self, decoder: JSONDecoder = .supabase()
  ) throws -> T {
    do {
      return try values.decode(as: T.self, decoder: decoder)
    } catch {
      throw RealtimeError(
        kind: .decoding, message: "row did not decode as \(T.self)", underlyingError: error)
    }
  }
}

/// A ``PostgresChange`` bound to a row type. Call ``row()`` to decode the record.
///
/// `Row` is a phantom type: no `Row` value is stored, so the change is `Sendable` for any `Row`.
public struct TypedPostgresChange<Row: Decodable>: Sendable {
  /// The change as the server sent it.
  public var raw: PostgresChange
  // `JSONDecoder` is `Sendable` only from iOS 17 and macOS 14. Nothing mutates it after the call
  // that made this change.
  package let decoder: UncheckedSendable<JSONDecoder>

  package init(raw: PostgresChange, decoder: JSONDecoder) {
    self.raw = raw
    self.decoder = UncheckedSendable(decoder)
  }

  /// The statement that made the change.
  public var kind: PostgresChange.Kind { raw.kind }

  /// The row before the change. It stays untyped: under row level security it holds only the
  /// primary key columns and would not decode as `Row`.
  public var oldRecord: PostgresRow? { raw.oldRecord }

  /// Decodes the record as `Row`.
  ///
  /// - Throws: ``RealtimeError`` of kind ``RealtimeError/Kind/decoding`` for a delete, which has
  ///   no record, or when the record does not decode.
  public func row() throws -> Row {
    guard let record = raw.record else {
      throw RealtimeError(kind: .decoding, message: "a \(kind) change has no record")
    }
    return try record.decode(as: Row.self, decoder: decoder.value)
  }
}

/// A stream element made from a ``PostgresChange`` and a decoder.
///
/// The typed stream builds its elements through this protocol so the closure captures only the
/// `Sendable` element type, not the row type, whose `Decodable` conformance may be isolated to the
/// caller's actor.
package protocol PostgresChangeElement: Sendable {
  init(raw: PostgresChange, decoder: JSONDecoder)
}

extension PostgresChangeElement {
  /// Wraps each change with `decoder`.
  package static func wrapping(decoder: JSONDecoder) -> @Sendable (PostgresChange) -> Self {
    // `JSONDecoder` is `Sendable` only from iOS 17 and macOS 14. Nothing mutates it after the call.
    let decoder = UncheckedSendable(decoder)
    return { Self(raw: $0, decoder: decoder.value) }
  }
}

extension TypedPostgresChange: PostgresChangeElement {}
