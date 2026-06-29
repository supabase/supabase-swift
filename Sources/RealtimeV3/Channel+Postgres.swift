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
      channelID: ObjectIdentifier(self)
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
      channelID: ObjectIdentifier(self)
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
      channelID: ObjectIdentifier(self)
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
      channelID: ObjectIdentifier(self)
    )
    _appendRegistration(config)
    return ChangeRegistration(config: config)
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
