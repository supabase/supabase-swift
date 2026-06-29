//
//  ChangeRegistration.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation

// MARK: - ChangeEventVariant

/// Variant protocol — each variant is itself generic over the row type and
/// declares the element type of `postgresChanges(for:)` for that variant.
public protocol ChangeEventVariant: Sendable {
  associatedtype Element: Sendable
}

// MARK: - Variant types

/// Variant for INSERT events. The stream element is the decoded row `T`.
public enum Insert<T: Sendable>: ChangeEventVariant {
  public typealias Element = T
}

/// Variant for UPDATE events. The stream element wraps the new record and
/// optional old record raw JSON.
public enum Update<T: Sendable>: ChangeEventVariant {
  public typealias Element = PostgresUpdate<T>
}

/// Variant for DELETE events. The stream element wraps the old record raw JSON.
public enum Delete<T: Sendable>: ChangeEventVariant {
  public typealias Element = PostgresDelete<T>
}

/// Variant that receives INSERT, UPDATE, and DELETE events combined.
public enum AnyEvent<T: Sendable>: ChangeEventVariant {
  public typealias Element = PostgresChange<T>
}

// MARK: - Element wrapper types

/// Wraps an UPDATE event with the new fully-decoded record and the raw old record.
///
/// The backend does not guarantee `oldRecord` is a full row unless the table
/// has `REPLICA IDENTITY FULL` set and RLS permits reading the old values.
public struct PostgresUpdate<T: Sendable>: Sendable {
  /// Fully decoded new row.
  public let record: T
  /// Raw old record. May contain only key columns under default `REPLICA IDENTITY`.
  public let oldRecord: JSONValue?
}

/// Wraps a DELETE event with the raw old record.
///
/// The full old row is only available when the table has `REPLICA IDENTITY FULL`
/// and the caller has read access via RLS.
public struct PostgresDelete<T: Sendable>: Sendable {
  /// Raw old record.
  public let oldRecord: JSONValue
}

/// Tagged union of all postgres change variants for use with `AnyEvent`.
public enum PostgresChange<T: Sendable>: Sendable {
  case insert(T)
  case update(PostgresUpdate<T>)
  case delete(PostgresDelete<T>)
}

// MARK: - Event mask

/// The event mask sent to the server in the postgres_changes entry.
enum PostgresEventMask: String, Sendable {
  case insert = "INSERT"
  case update = "UPDATE"
  case delete = "DELETE"
  case all = "*"
}

// MARK: - VariantKind

/// Discriminator for the variant type at the `ChangeRegistrationConfig` level.
///
/// Stored in `ChangeRegistrationConfig` so `Channel.postgresChanges(for:)` can switch on the
/// known variant kind and build the type-erased decode+yield closure without needing to
/// keep the generic type parameter `E` in the registry (which would require existential boxing).
///
/// The mapping is:
/// - `.insert`  → `Insert<JSONValue>`, `E.Element == JSONValue`
/// - `.update`  → `Update<JSONValue>`, `E.Element == PostgresUpdate<JSONValue>`
/// - `.delete`  → `Delete<JSONValue>`, `E.Element == PostgresDelete<JSONValue>`
/// - `.anyEvent`→ `AnyEvent<JSONValue>`, `E.Element == PostgresChange<JSONValue>`
enum VariantKind: Sendable {
  case insert
  case update
  case delete
  case anyEvent
}

// MARK: - ChangeRegistrationConfig

/// Internal descriptor of a postgres-changes registration. Captured in
/// `ChangeRegistration<E>` and serialised into the `phx_join` payload.
struct ChangeRegistrationConfig: Sendable {
  var event: PostgresEventMask
  var schema: String
  var table: String
  /// Serialized filter string (e.g. `"room_id=eq.1"`). `nil` means no filter.
  var filter: String?
  /// Stable per-registration identifier used for server-id routing (Task 28).
  let id: UUID
  /// Identity of the owning channel — used by Task 28 to detect `.unknownToken`.
  let channelID: ObjectIdentifier
  /// The variant kind — used by Task 28 to build the type-erased decode/yield closure.
  let variantKind: VariantKind
}

// MARK: - ChangeRegistration

/// An opaque token that records a postgres-changes subscription intent.
///
/// Obtain tokens via `channel.inserts(...)`, `channel.updates(...)`,
/// `channel.deletes(...)`, or `channel.changes(...)` **before** calling
/// `channel.subscribe()`. Each factory appends the token to the channel's
/// pending-registration set; when `subscribe()` triggers the `phx_join`
/// handshake those entries are baked into `config.postgres_changes`.
///
/// **Reusable across subscribe cycles.** After `channel.leave()` the same
/// token replays on the next `channel.subscribe()`. Registering new tokens
/// while the channel is `.joined` or `.joining` throws
/// `.cannotRegisterAfterJoin`.
///
/// The generic parameter `E` is a `ChangeEventVariant` that determines the
/// element type of the `postgresChanges(for:)` stream (Task 28). Its internal
/// state is not public — callers treat this type as opaque.
public struct ChangeRegistration<E: ChangeEventVariant>: Sendable {
  /// Internal config read by `Channel` to build the `phx_join` payload and
  /// by Task 28 to route incoming server events.
  let config: ChangeRegistrationConfig
}
