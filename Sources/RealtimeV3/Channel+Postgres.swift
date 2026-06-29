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

    let id = UUID()
    let (stream, continuation) = AsyncThrowingStream<E.Element, any Error>.makeStream()

    // Capture the variantKind at registration time.
    let variantKind = config.variantKind
    let registrationID = config.id

    // Type-erased handler. Called by _routePostgresChange for each matching server id.
    // We switch on variantKind — safe `as!` because the variant kind is immutably tied
    // to the generic parameter E at factory call time.
    let handler: @Sendable (PhoenixMessage) -> Void = { message in
      guard case .json(let jsonValue) = message.payload,
        let obj = jsonValue.objectValue,
        let dataValue = obj["data"],
        let dataObj = dataValue.objectValue
      else { return }

      let type_ = dataObj["type"]?.stringValue ?? ""
      let record: JSONValue = dataObj["record"] ?? .object([:])
      let oldRecord: JSONValue? = dataObj["old_record"]

      let element: E.Element
      switch variantKind {
      case .insert:
        // E == Insert<JSONValue>, E.Element == JSONValue
        element = record as! E.Element

      case .update:
        // E == Update<JSONValue>, E.Element == PostgresUpdate<JSONValue>
        let update = PostgresUpdate<JSONValue>(record: record, oldRecord: oldRecord)
        element = update as! E.Element

      case .delete:
        // E == Delete<JSONValue>, E.Element == PostgresDelete<JSONValue>
        let oldRec = oldRecord ?? .object([:])
        let del = PostgresDelete<JSONValue>(oldRecord: oldRec)
        element = del as! E.Element

      case .anyEvent:
        // E == AnyEvent<JSONValue>, E.Element == PostgresChange<JSONValue>
        let change: PostgresChange<JSONValue>
        switch type_ {
        case "INSERT":
          change = .insert(record)
        case "UPDATE":
          let update = PostgresUpdate<JSONValue>(record: record, oldRecord: oldRecord)
          change = .update(update)
        case "DELETE":
          let oldRec = oldRecord ?? .object([:])
          let del = PostgresDelete<JSONValue>(oldRecord: oldRec)
          change = .delete(del)
        default:
          // Unknown event type — treat as insert with the raw data value.
          change = .insert(record)
        }
        element = change as! E.Element
      }
      continuation.yield(element)
    }

    // Channel-close finisher: throws .channelClosed(reason) into the stream.
    let finisher: @Sendable (CloseReason) -> Void = { reason in
      continuation.finish(throwing: RealtimeError.channelClosed(reason))
    }

    // System postgres error finisher: throws .postgresSubscriptionFailed(reason:).
    let errorFinisher: @Sendable (String) -> Void = { reason in
      continuation.finish(throwing: RealtimeError.postgresSubscriptionFailed(reason: reason))
    }

    // Register all three in the actor's fan-out tables.
    postgresConsumers[id] = handler
    postgresFinishers[id] = finisher
    postgresErrorFinishers[id] = errorFinisher

    // Register this consumer UUID in the indirection map: registrationID → [consumerIDs].
    if registrationConsumers[registrationID] == nil {
      registrationConsumers[registrationID] = [id]
    } else {
      registrationConsumers[registrationID]?.append(id)
    }

    // On stream termination (cancellation or normal finish), deregister from the actor.
    continuation.onTermination = { [weak self] _ in
      Task { [weak self] in
        await self?.removePostgresConsumer(id: id, registrationID: registrationID)
      }
    }

    return stream
  }
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
