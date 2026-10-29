//
//  PostgresChange.swift
//  Realtime
//
//  Created by Guilherme Souza on 29/10/26.
//

import ConcurrencyExtras
public import Foundation

/// A row change the server read from the Postgres write-ahead log.
///
/// Read it from ``RealtimeChannel/postgresChanges(event:schema:table:filter:select:)``, or use
/// ``RealtimeChannel/postgresChanges(of:event:schema:table:filter:select:decoder:)`` to get a
/// ``TypedPostgresChange`` that decodes the row for you.
public struct PostgresChange: Sendable, Hashable {
  /// The statement that made a change.
  ///
  /// The server owns this set, so compare against the static members and keep a fallback
  /// branch.
  public struct Kind: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
      self.init(rawValue: value)
    }

    /// A row was inserted.
    public static let insert: Kind = "INSERT"
    /// A row was updated.
    public static let update: Kind = "UPDATE"
    /// A row was deleted.
    public static let delete: Kind = "DELETE"
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
  init(payload: JSONObject) throws(RealtimeError) {
    guard let type = payload["type"]?.stringValue else {
      throw RealtimeError.decoding("Postgres change without a type.")
    }
    guard let schema = payload["schema"]?.stringValue, let table = payload["table"]?.stringValue
    else {
      throw RealtimeError.decoding("Postgres change without a schema or table.")
    }
    guard let timestamp = payload["commit_timestamp"]?.stringValue, let date = timestamp.date else {
      throw RealtimeError.decoding("Postgres change without a valid commit_timestamp.")
    }
    kind = Kind(rawValue: type)
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

/// A column of the table a ``PostgresChange`` changed.
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
  /// - Parameters:
  ///   - type: The type to decode. Can be inferred from context.
  ///   - decoder: The decoder to use. Defaults to the decoder the SDK uses for server responses.
  /// - Throws: ``RealtimeError`` of kind ``RealtimeError/Kind/decoding`` when the row does not
  ///   decode as `T`. The underlying `DecodingError` is in ``RealtimeError/underlyingError``.
  public func decode<T: Decodable>(
    as _: T.Type = T.self, decoder: JSONDecoder = .supabase()
  ) throws -> T {
    do {
      return try values.decode(as: T.self, decoder: decoder)
    } catch {
      throw RealtimeError(
        kind: .decoding, message: "Row did not decode as \(T.self).", isRetryable: false,
        underlyingError: error)
    }
  }
}

/// A ``PostgresChange`` bound to a row type. Call ``row()`` to decode the record.
///
/// The SDK does not decode the row before it delivers the change, so a row that does not decode
/// never drops the change or ends the stream: ``row()`` throws at the call site instead.
///
/// `Row` is a phantom type: no `Row` value is stored, so the change is `Sendable` for any `Row`.
/// Only ``row()`` needs `Row: Decodable`, so a row type whose `Decodable` conformance is isolated
/// to the main actor works from the main actor.
public struct TypedPostgresChange<Row>: Sendable {
  /// The change as the server sent it.
  public var raw: PostgresChange
  // `JSONDecoder` is `Sendable` only from iOS 17 and macOS 14. Nothing mutates it after the call
  // that made this change.
  let decoder: UncheckedSendable<JSONDecoder>

  init(raw: PostgresChange, decoder: JSONDecoder) {
    self.raw = raw
    self.decoder = UncheckedSendable(decoder)
  }

  /// The statement that made the change.
  public var kind: PostgresChange.Kind { raw.kind }

  /// The row before the change. It stays untyped: without `REPLICA IDENTITY FULL`, or under row
  /// level security, it holds only the primary key columns and would not decode as `Row`.
  public var oldRecord: PostgresRow? { raw.oldRecord }
}

extension TypedPostgresChange where Row: Decodable {
  /// Decodes the record as `Row`.
  ///
  /// - Throws: ``RealtimeError`` of kind ``RealtimeError/Kind/decoding`` for a change with no
  ///   record, such as a delete, or when the record does not decode as `Row`.
  public func row() throws -> Row {
    guard let record = raw.record else {
      throw RealtimeError.decoding("A \(kind.rawValue) change has no record.")
    }
    return try record.decode(as: Row.self, decoder: decoder.value)
  }
}
