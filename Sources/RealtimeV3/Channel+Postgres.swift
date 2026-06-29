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

    // Subscribe to the channel's event feed synchronously (on-actor).
    let base = _subscribeEvents()

    return AsyncThrowingStream<E.Element, any Error> { continuation in
      let task = Task { [weak self] in
        for await channelEvent in base {
          switch channelEvent {
          case .terminated(let reason):
            // Terminal close: throws .channelClosed(reason) into the stream.
            continuation.finish(throwing: RealtimeError.channelClosed(reason))
            return

          case .message(let message):
            switch message.event {
            case .system:
              // postgres_changes subscription error (H6) → fail this stream with
              // .postgresSubscriptionFailed. Other system events are ignored here.
              guard case .json(let jsonValue) = message.payload,
                let obj = jsonValue.objectValue,
                obj["extension"]?.stringValue == "postgres_changes",
                obj["status"]?.stringValue == "error"
              else { continue }
              let reason = obj["message"]?.stringValue ?? "Unknown postgres subscription error"
              continuation.finish(
                throwing: RealtimeError.postgresSubscriptionFailed(reason: reason))
              return

            case .postgresChanges:
              // Does this frame target our registration? Match the frame's `ids` against
              // the server ids currently mapped to our registration (read live, since the
              // mapping is rebuilt on every rejoin).
              guard case .json(let jsonValue) = message.payload,
                let obj = jsonValue.objectValue,
                let idsArray = obj["ids"]?.arrayValue,
                let dataObj = obj["data"]?.objectValue
              else { continue }

              let frameIDs = Set(idsArray.compactMap { $0.intValue })
              guard !frameIDs.isEmpty else { continue }

              let myServerIDs = await self?.postgresServerIDs(for: registrationID) ?? []
              guard !myServerIDs.isDisjoint(with: frameIDs) else { continue }

              // Decode E.Element from the data object. Safe `as!`: the variant kind is
              // immutably tied to the generic parameter E at factory call time. A malformed
              // frame finishes THIS stream with `.decoding`.
              let type_ = dataObj["type"]?.stringValue ?? ""
              let element: E.Element
              switch variantKind {
              case .insert:
                // E == Insert<JSONValue>, E.Element == JSONValue
                guard let record = dataObj["record"] else {
                  continuation.finish(throwing: decodeError("Insert<JSONValue>: missing record"))
                  return
                }
                element = record as! E.Element

              case .update:
                // E == Update<JSONValue>, E.Element == PostgresUpdate<JSONValue>
                guard let record = dataObj["record"] else {
                  continuation.finish(throwing: decodeError("Update<JSONValue>: missing record"))
                  return
                }
                let oldRecord: JSONValue? = dataObj["old_record"]
                let update = PostgresUpdate<JSONValue>(record: record, oldRecord: oldRecord)
                element = update as! E.Element

              case .delete:
                // E == Delete<JSONValue>, E.Element == PostgresDelete<JSONValue>
                // old_record is NON-optional for DELETE; absence is a decode failure.
                guard let oldRecord = dataObj["old_record"] else {
                  continuation.finish(
                    throwing: decodeError("Delete<JSONValue>: missing old_record"))
                  return
                }
                let del = PostgresDelete<JSONValue>(oldRecord: oldRecord)
                element = del as! E.Element

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
                  continuation.finish(
                    throwing: decodeError("AnyEvent<JSONValue>: unknown type '\(type_)'"))
                  return
                }
                element = change as! E.Element
              }
              continuation.yield(element)

            default:
              continue
            }
          }
        }
        // Feed ended without an explicit terminal event (e.g. channel deallocated).
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
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
