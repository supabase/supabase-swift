//
//  Channel+Postgres.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation

// MARK: - Pending registration storage

extension Channel {
  /// Appends a `ChangeRegistrationConfig` to the channel's pending-registration set.
  ///
  /// Called by every untyped factory after the state guard passes.
  func _appendRegistration(_ config: ChangeRegistrationConfig) {
    pendingRegistrations.append(config)
  }
}

// MARK: - Untyped factories (§5.3 / §5.4)

extension Channel {
  // -----------------------------------------------------------------------
  // All factories are isolated (they mutate `pendingRegistrations`) so
  // callers must `await` them. They are `async throws(RealtimeError)` so
  // they can throw `.cannotRegisterAfterJoin` when the channel is already
  // `.joined` or `.joining`.
  //
  // Design note: the spec signature (§5.3) shows these as returning
  // `ChangeRegistration<E>` directly (no explicit `async throws`), but the
  // spec prose (§2.1, §5.3) states they are isolated and throw after join.
  // We resolve toward `async throws(RealtimeError)` to satisfy the isolation
  // contract and the typed-throw requirement — the `await` is mandatory when
  // calling any isolated actor method in Swift 6 anyway.
  // -----------------------------------------------------------------------

  /// Registers a subscription for ALL postgres change events (`INSERT`, `UPDATE`,
  /// `DELETE`) on the given schema+table.
  ///
  /// Must be called before `subscribe()`. Throws `.cannotRegisterAfterJoin`
  /// if the channel is already `.joined` or `.joining`.
  ///
  /// - Parameters:
  ///   - schema: Postgres schema (e.g. `"public"`).
  ///   - table: Postgres table name.
  ///   - filter: Optional row filter (`UntypedFilter`). `nil` means no filter.
  /// - Returns: An opaque `ChangeRegistration<AnyEvent<JSONValue>>` token.
  public func changes(
    schema: String,
    table: String,
    filter: UntypedFilter? = nil
  ) async throws(RealtimeError) -> ChangeRegistration<AnyEvent<JSONValue>> {
    try _guardCanRegister()
    let config = ChangeRegistrationConfig(
      event: .all,
      schema: schema,
      table: table,
      filter: filter?.serialized,
      id: UUID(),
      channelID: ObjectIdentifier(self),
      variantKind: .anyEvent
    )
    _appendRegistration(config)
    return ChangeRegistration(config: config)
  }

  /// Registers a subscription for INSERT events on the given schema+table.
  ///
  /// Must be called before `subscribe()`. Throws `.cannotRegisterAfterJoin`
  /// if the channel is already `.joined` or `.joining`.
  ///
  /// - Parameters:
  ///   - schema: Postgres schema (e.g. `"public"`).
  ///   - table: Postgres table name.
  ///   - filter: Optional row filter (`UntypedFilter`). `nil` means no filter.
  /// - Returns: An opaque `ChangeRegistration<Insert<JSONValue>>` token.
  public func inserts(
    schema: String,
    table: String,
    filter: UntypedFilter? = nil
  ) async throws(RealtimeError) -> ChangeRegistration<Insert<JSONValue>> {
    try _guardCanRegister()
    let config = ChangeRegistrationConfig(
      event: .insert,
      schema: schema,
      table: table,
      filter: filter?.serialized,
      id: UUID(),
      channelID: ObjectIdentifier(self),
      variantKind: .insert
    )
    _appendRegistration(config)
    return ChangeRegistration(config: config)
  }

  /// Registers a subscription for UPDATE events on the given schema+table.
  ///
  /// Must be called before `subscribe()`. Throws `.cannotRegisterAfterJoin`
  /// if the channel is already `.joined` or `.joining`.
  ///
  /// - Parameters:
  ///   - schema: Postgres schema (e.g. `"public"`).
  ///   - table: Postgres table name.
  ///   - filter: Optional row filter (`UntypedFilter`). `nil` means no filter.
  /// - Returns: An opaque `ChangeRegistration<Update<JSONValue>>` token.
  public func updates(
    schema: String,
    table: String,
    filter: UntypedFilter? = nil
  ) async throws(RealtimeError) -> ChangeRegistration<Update<JSONValue>> {
    try _guardCanRegister()
    let config = ChangeRegistrationConfig(
      event: .update,
      schema: schema,
      table: table,
      filter: filter?.serialized,
      id: UUID(),
      channelID: ObjectIdentifier(self),
      variantKind: .update
    )
    _appendRegistration(config)
    return ChangeRegistration(config: config)
  }

  /// Registers a subscription for DELETE events on the given schema+table.
  ///
  /// Must be called before `subscribe()`. Throws `.cannotRegisterAfterJoin`
  /// if the channel is already `.joined` or `.joining`.
  ///
  /// - Parameters:
  ///   - schema: Postgres schema (e.g. `"public"`).
  ///   - table: Postgres table name.
  ///   - filter: Optional row filter (`UntypedFilter`). `nil` means no filter.
  /// - Returns: An opaque `ChangeRegistration<Delete<JSONValue>>` token.
  public func deletes(
    schema: String,
    table: String,
    filter: UntypedFilter? = nil
  ) async throws(RealtimeError) -> ChangeRegistration<Delete<JSONValue>> {
    try _guardCanRegister()
    let config = ChangeRegistrationConfig(
      event: .delete,
      schema: schema,
      table: table,
      filter: filter?.serialized,
      id: UUID(),
      channelID: ObjectIdentifier(self),
      variantKind: .delete
    )
    _appendRegistration(config)
    return ChangeRegistration(config: config)
  }
}

// MARK: - postgresChanges(for:) (Task 28)

// Small sendable error carrying a plain string description, used as the `underlying`
// value in `RealtimeError.decoding` when no root-cause `Error` is available.
struct PostgresDecodeError: Error, Sendable, CustomStringConvertible {
  let description: String
}

extension Channel {
  /// Returns an `AsyncThrowingStream` that yields every postgres change event that
  /// matches the given registration token.
  ///
  /// ## Server-id routing
  /// The server assigns integer ids to each `postgres_changes` entry in the join reply
  /// (in the same order as the client's `postgres_changes` array). An incoming
  /// `postgres_changes` frame carries an `ids` array; this method routes the frame to
  /// all tokens whose registration UUID is mapped to one of those server ids.
  ///
  /// ## Per-call fan-out (Decision 12 OR semantics)
  /// Multiple `postgresChanges(for:)` calls for tokens sharing a server id each receive
  /// a copy of every matching frame.
  ///
  /// ## `.unknownToken`
  /// If `token` was created on a different channel, the returned stream immediately
  /// finishes throwing `.unknownToken`.
  ///
  /// ## Decode failure
  /// If the frame cannot be decoded into `E.Element`, the stream terminates by
  /// throwing `RealtimeError.decoding(type:underlying:)`.
  ///
  /// ## Terminal close
  /// When the channel transitions to `.closed(reason)`, the stream terminates by
  /// throwing `RealtimeError.channelClosed(reason)`.
  ///
  /// ## Async setup errors (H6)
  /// When a `system` event signals a postgres_changes failure, the stream terminates
  /// by throwing `RealtimeError.postgresSubscriptionFailed(reason:)`.
  ///
  /// - Note: The thrown error is always a `RealtimeError`. The stream's `Failure` is
  ///   `any Error` (not `RealtimeError`) because `AsyncThrowingStream<_, RealtimeError>`
  ///   requires iOS 17+; on the iOS 16 deployment target, only `Failure == any Error` is
  ///   available. Cast with `as? RealtimeError` or use `if case` matching.
  public func postgresChanges<E: ChangeEventVariant>(
    for token: ChangeRegistration<E>
  ) -> AsyncThrowingStream<E.Element, any Error> {
    let config = token.config

    // Guard: token must belong to this channel.
    guard config.channelID == ObjectIdentifier(self) else {
      let (stream, continuation) = AsyncThrowingStream<E.Element, any Error>.makeStream()
      continuation.finish(throwing: RealtimeError.unknownToken)
      return stream
    }

    // Capture the variantKind + registration id at registration time.
    let variantKind = config.variantKind
    let registrationID = config.id

    // The helper handles terminal close (→ `.channelClosed`) and task lifecycle. The body
    // self-filters the feed: a `system` postgres error fails the stream (H6); a matching
    // `postgres_changes` frame is decoded and yielded; a malformed frame throws `.decoding`.
    return _makeThrowingStream(initialState: ()) { [weak self] _, message, continuation in
      switch message.event {
      case .system:
        // postgres_changes subscription error (H6) → fail this stream.
        guard let system = SystemEventPayload(message),
          system.isPostgresChanges, system.status == "error"
        else { return }
        let reason = system.message ?? "Unknown postgres subscription error"
        throw RealtimeError.postgresSubscriptionFailed(reason: reason)

      case .postgresChanges:
        // Does this frame target our registration? Match the frame's `ids` against the
        // server ids currently mapped to our registration (read live, since the mapping
        // is rebuilt on every rejoin).
        guard case .json(let jsonValue) = message.payload,
          let obj = jsonValue.objectValue,
          let idsArray = obj["ids"]?.arrayValue,
          let dataObj = obj["data"]?.objectValue
        else { return }

        let frameIDs = Set(idsArray.compactMap { $0.intValue })
        guard !frameIDs.isEmpty else { return }

        let myServerIDs = await self?.postgresServerIDs(for: registrationID) ?? []
        guard !myServerIDs.isDisjoint(with: frameIDs) else { return }

        // Decode E.Element from the data object. Safe `as!`: the variant kind is immutably
        // tied to the generic parameter E at factory call time. A malformed frame throws.
        let type_ = dataObj["type"]?.stringValue ?? ""
        let element: E.Element
        switch variantKind {
        case .insert:
          // E == Insert<JSONValue>, E.Element == JSONValue
          guard let record = dataObj["record"] else {
            throw decodeError("Insert<JSONValue>: missing record")
          }
          element = try postgresElement(record, for: E.self)

        case .update:
          // E == Update<JSONValue>, E.Element == PostgresUpdate<JSONValue>
          guard let record = dataObj["record"] else {
            throw decodeError("Update<JSONValue>: missing record")
          }
          let oldRecord: JSONValue? = dataObj["old_record"]
          let update = PostgresUpdate<JSONValue>(record: record, oldRecord: oldRecord)
          element = try postgresElement(update, for: E.self)

        case .delete:
          // E == Delete<JSONValue>, E.Element == PostgresDelete<JSONValue>
          // old_record is NON-optional for DELETE; absence is a decode failure.
          guard let oldRecord = dataObj["old_record"] else {
            throw decodeError("Delete<JSONValue>: missing old_record")
          }
          let del = PostgresDelete<JSONValue>(oldRecord: oldRecord)
          element = try postgresElement(del, for: E.self)

        case .anyEvent:
          // E == AnyEvent<JSONValue>, E.Element == PostgresChange<JSONValue>
          let change: PostgresChange<JSONValue>
          switch type_ {
          case "INSERT":
            let record: JSONValue = dataObj["record"] ?? .object([:])
            change = .insert(record)
          case "UPDATE":
            let record: JSONValue = dataObj["record"] ?? .object([:])
            let oldRecord: JSONValue? = dataObj["old_record"]
            let update = PostgresUpdate<JSONValue>(record: record, oldRecord: oldRecord)
            change = .update(update)
          case "DELETE":
            let oldRecord: JSONValue = dataObj["old_record"] ?? .object([:])
            let del = PostgresDelete<JSONValue>(oldRecord: oldRecord)
            change = .delete(del)
          default:
            // Unrecognized event type is a decode failure for this stream.
            throw decodeError("AnyEvent<JSONValue>: unknown type '\(type_)'")
          }
          element = try postgresElement(change, for: E.self)
        }
        continuation.yield(element)

      default:
        return
      }
    }
  }
}

/// Builds a `.decoding` error for a malformed `postgres_changes` frame.
private func decodeError(_ typeDescription: String) -> RealtimeError {
  RealtimeError.decoding(
    type: typeDescription,
    underlying: PostgresDecodeError(description: "malformed postgres_changes data")
  )
}

/// Casts a constructed variant payload to `E.Element`. The cast holds by construction —
/// `variantKind` is bound to `E` at registration — but throwing instead of force-casting honors
/// the never-crash policy should that invariant ever be violated.
private func postgresElement<E: ChangeEventVariant>(
  _ value: Any, for _: E.Type
) throws(RealtimeError) -> E.Element {
  guard let element = value as? E.Element else {
    throw decodeError("postgres_changes element type mismatch for \(E.Element.self)")
  }
  return element
}

// MARK: - State guard (internal)

extension Channel {
  /// Throws `.cannotRegisterAfterJoin` if the channel is in a state where
  /// postgres-changes registration is no longer allowed.
  ///
  /// Registration is permitted in `.unsubscribed` and `.closed` states — i.e.
  /// any state where a `phx_join` has not yet been sent or is no longer active.
  func _guardCanRegister() throws(RealtimeError) {
    switch channelState {
    case .unsubscribed, .closed:
      return  // Allowed.
    case .joining, .joined, .leaving:
      throw .cannotRegisterAfterJoin
    }
  }
}
