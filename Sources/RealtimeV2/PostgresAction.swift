//
//  PostgresAction.swift
//
//
//  Created by Guilherme Souza on 23/12/23.
//

public import Foundation

/// Describes a single column returned in a Postgres change event.
///
/// ## Topics
/// ### Properties
/// - ``name``
/// - ``type``
public struct Column: Equatable, Codable, Sendable {
  /// The column name in the database.
  public let name: String

  /// The PostgreSQL type of the column (e.g. `"int4"`, `"text"`, `"timestamptz"`).
  public let type: String
}

/// A Postgres row change event received from the Realtime server.
///
/// Concrete types conforming to this protocol are ``InsertAction``, ``UpdateAction``,
/// ``DeleteAction``, and ``AnyAction``.
///
/// ## Topics
/// ### Associated Event
/// - ``eventType``
public protocol PostgresAction: Equatable, Sendable {
  /// The Postgres change event type this action represents.
  static var eventType: PostgresChangeEvent { get }
}

/// An action that carries the new row data after an `INSERT` or `UPDATE`.
///
/// Use ``decodeRecord(as:decoder:)`` to decode the ``record`` into a `Decodable` model.
public protocol HasRecord {
  /// The current row data as a ``JSONObject``, keyed by column name.
  var record: JSONObject { get }
}

/// An action that carries the previous row data before an `UPDATE` or `DELETE`.
///
/// Use ``decodeOldRecord(as:decoder:)`` to decode the ``oldRecord`` into a `Decodable` model.
public protocol HasOldRecord {
  /// The previous row data as a ``JSONObject``, keyed by column name, before the change was applied.
  var oldRecord: JSONObject { get }
}

/// An action that exposes the raw ``RealtimeMessageV2`` received from the server.
public protocol HasRawMessage {
  /// The underlying Realtime message that triggered this action.
  var rawMessage: RealtimeMessageV2 { get }
}

/// A Postgres `INSERT` change event.
///
/// Received when a new row is inserted into a tracked table.
/// Contains the new row's data in ``record``.
///
/// ## Topics
/// ### Properties
/// - ``columns``
/// - ``commitTimestamp``
/// - ``record``
/// - ``rawMessage``
public struct InsertAction: PostgresAction, HasRecord, HasRawMessage {
  /// The change event type, always ``PostgresChangeEvent/insert``.
  public static let eventType: PostgresChangeEvent = .insert

  /// The column definitions for the affected table at the time of the change.
  public let columns: [Column]

  /// The timestamp at which this change was committed in the database.
  public let commitTimestamp: Date

  /// The newly-inserted row's data, keyed by column name.
  public let record: [String: AnyJSON]

  /// The raw Realtime message that delivered this event.
  public let rawMessage: RealtimeMessageV2
}

/// A Postgres `UPDATE` change event.
///
/// Received when an existing row is updated in a tracked table.
/// Contains both the new row data in ``record`` and the previous data in ``oldRecord``.
///
/// ## Topics
/// ### Properties
/// - ``columns``
/// - ``commitTimestamp``
/// - ``record``
/// - ``oldRecord``
/// - ``rawMessage``
public struct UpdateAction: PostgresAction, HasRecord, HasOldRecord, HasRawMessage {
  /// The change event type, always ``PostgresChangeEvent/update``.
  public static let eventType: PostgresChangeEvent = .update

  /// The column definitions for the affected table at the time of the change.
  public let columns: [Column]

  /// The timestamp at which this change was committed in the database.
  public let commitTimestamp: Date

  /// The updated row's new data, keyed by column name.
  public let record: [String: AnyJSON]

  /// The row's data before the update was applied, keyed by column name.
  public let oldRecord: [String: AnyJSON]

  /// The raw Realtime message that delivered this event.
  public let rawMessage: RealtimeMessageV2
}

/// A Postgres `DELETE` change event.
///
/// Received when a row is deleted from a tracked table.
/// Contains the deleted row's previous data in ``oldRecord``.
///
/// ## Topics
/// ### Properties
/// - ``columns``
/// - ``commitTimestamp``
/// - ``oldRecord``
/// - ``rawMessage``
public struct DeleteAction: PostgresAction, HasOldRecord, HasRawMessage {
  /// The change event type, always ``PostgresChangeEvent/delete``.
  public static let eventType: PostgresChangeEvent = .delete

  /// The column definitions for the affected table at the time of the change.
  public let columns: [Column]

  /// The timestamp at which this change was committed in the database.
  public let commitTimestamp: Date

  /// The deleted row's data before removal, keyed by column name.
  public let oldRecord: [String: AnyJSON]

  /// The raw Realtime message that delivered this event.
  public let rawMessage: RealtimeMessageV2
}

/// A Postgres change event that wraps any of the concrete action types.
///
/// Use this type when you want to receive `INSERT`, `UPDATE`, and `DELETE` changes
/// with a single async stream. Pattern-match on the cases to access the underlying action.
///
/// ```swift
/// let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "messages")
/// try await channel.subscribeWithError()
/// for await action in changes {
///   switch action {
///   case .insert(let insert): print(insert.record)
///   case .update(let update): print(update.record)
///   case .delete(let delete): print(delete.oldRecord)
///   }
/// }
/// ```
///
/// ## Topics
/// ### Cases
/// - ``insert(_:)``
/// - ``update(_:)``
/// - ``delete(_:)``
/// ### Properties
/// - ``rawMessage``
public enum AnyAction: PostgresAction, HasRawMessage {
  /// The event type for this enum, always ``PostgresChangeEvent/all``.
  public static let eventType: PostgresChangeEvent = .all

  /// An `INSERT` event wrapping an ``InsertAction``.
  case insert(InsertAction)

  /// An `UPDATE` event wrapping an ``UpdateAction``.
  case update(UpdateAction)

  /// A `DELETE` event wrapping a ``DeleteAction``.
  case delete(DeleteAction)

  var wrappedAction: any PostgresAction & HasRawMessage {
    switch self {
    case .insert(let action): action
    case .update(let action): action
    case .delete(let action): action
    }
  }

  /// The raw Realtime message from the server that delivered this action.
  public var rawMessage: RealtimeMessageV2 {
    wrappedAction.rawMessage
  }
}

extension HasRecord {
  /// Decodes the ``record`` dictionary into a `Decodable` model.
  ///
  /// - Parameters:
  ///   - type: The target `Decodable` type. Can be inferred from context.
  ///   - decoder: A `JSONDecoder` to use for decoding. Defaults to `AnyJSON.decoder`.
  /// - Returns: An instance of `T` decoded from the record data.
  /// - Throws: A `DecodingError` if the record cannot be decoded into `T`.
  public func decodeRecord<T: Decodable>(as _: T.Type = T.self, decoder: JSONDecoder) throws -> T {
    try record.decode(as: T.self, decoder: decoder)
  }
}

extension HasOldRecord {
  /// Decodes the ``oldRecord`` dictionary into a `Decodable` model.
  ///
  /// - Parameters:
  ///   - type: The target `Decodable` type. Can be inferred from context.
  ///   - decoder: A `JSONDecoder` to use for decoding. Defaults to `AnyJSON.decoder`.
  /// - Returns: An instance of `T` decoded from the old record data.
  /// - Throws: A `DecodingError` if the old record cannot be decoded into `T`.
  public func decodeOldRecord<T: Decodable>(
    as _: T.Type = T.self,
    decoder: JSONDecoder
  ) throws -> T {
    try oldRecord.decode(as: T.self, decoder: decoder)
  }
}
