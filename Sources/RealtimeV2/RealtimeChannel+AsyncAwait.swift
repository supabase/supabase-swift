//
//  RealtimeChannel+AsyncAwait.swift
//
//
//  Created by Guilherme Souza on 17/04/24.
//

import ConcurrencyExtras
public import Foundation

extension RealtimeChannelV2 {
  /// Returns an async stream of server events about this channel.
  ///
  /// The stream emits ``RealtimeChannelEvent/resubscribed`` when the channel joins again after
  /// a reconnect, and reports whether the server set up the channel's Postgres changes
  /// subscriptions. The stream is registered before this method returns and emits only the
  /// events from then on; it never replays an earlier event. Read the channel's state with
  /// ``status`` and ``statusChanges()``. Cancelling the iterating task ends the stream.
  ///
  /// ```swift
  /// for await event in await channel.events() {
  ///   if event == .resubscribed {
  ///     await reloadMessages()
  ///   }
  /// }
  /// ```
  ///
  /// - Returns: An `AsyncStream` of ``RealtimeChannelEvent`` values.
  public func events() async -> AsyncStream<RealtimeChannelEvent> {
    let (stream, continuation) = AsyncStream<RealtimeChannelEvent>.makeStream()
    let id = UUID()
    eventObservers.withValue { $0.continuations[id] = continuation }
    continuation.onTermination = { [weak self] _ in
      self?.eventObservers.withValue { $0.continuations[id] = nil }
    }
    return stream
  }

  /// The clients present on the channel, as of the last presence sync.
  ///
  /// It is empty until the channel is subscribed with presence on, which needs a presence
  /// stream open when ``subscribeWithError()`` runs. It is empty again after ``unsubscribe()``.
  /// To observe the state, use ``presenceStates()``.
  public var presenceState: PresenceState {
    get async { presenceTracker.value.state }
  }

  /// Returns an async stream of the entries that join and leave the channel's presence.
  ///
  /// Each element holds the joins and leaves of one sync, by presence key. The first sync after
  /// a join reports the difference from the state the channel held, and ``unsubscribe()`` reports
  /// every client as a leave, so the changes always add up to ``presenceState``. A sync that
  /// changes nothing is not emitted.
  ///
  /// Having a presence stream open when ``subscribeWithError()`` runs is what enables presence on
  /// the channel, so open it before subscribing. Opening one after the channel started to
  /// subscribe reports an issue and returns a stream that ends at once. The stream ends when the
  /// iterating task is cancelled.
  ///
  /// - Returns: An `AsyncStream` of ``PresenceChange`` values.
  public func presenceChanges() async -> AsyncStream<PresenceChange> {
    let (stream, continuation) = AsyncStream<PresenceChange>.makeStream()

    let subscription = observePresence { delivery in
      guard let change = delivery.change, !change.isEmpty else { return }
      continuation.yield(change)
    }

    guard let subscription else {
      continuation.finish()
      return stream
    }

    continuation.onTermination = { _ in
      subscription.cancel()
    }
    return stream
  }

  /// Returns an async stream of the channel's presence state.
  ///
  /// The stream emits ``presenceState`` at once, then the new state after every presence sync
  /// that changes it.
  ///
  /// Having a presence stream open when ``subscribeWithError()`` runs is what enables presence on
  /// the channel, so open it before subscribing. Opening one after the channel started to
  /// subscribe reports an issue and returns a stream that ends at once. The stream ends when the
  /// iterating task is cancelled.
  ///
  /// - Returns: An `AsyncStream` of ``PresenceState`` values.
  public func presenceStates() async -> AsyncStream<PresenceState> {
    let (stream, continuation) = AsyncStream<PresenceState>.makeStream()

    let subscription = observePresence { delivery in
      guard let change = delivery.change, !change.isEmpty else { return }
      continuation.yield(delivery.state)
    }

    guard let subscription else {
      continuation.finish()
      return stream
    }

    continuation.yield(presenceTracker.value.state)
    continuation.onTermination = { _ in
      subscription.cancel()
    }
    return stream
  }

  /// Returns an async stream that emits a ``PresenceAction`` whenever clients join or leave.
  ///
  /// The stream terminates when the caller cancels the enclosing task or the channel is removed.
  /// Register this stream before calling ``subscribeWithError()``.
  ///
  /// - Returns: An `AsyncStream` of ``PresenceAction`` values.
  @available(*, deprecated, message: "Use presenceChanges() instead.")
  public func presenceChange() -> AsyncStream<any PresenceAction> {
    let (stream, continuation) = AsyncStream<any PresenceAction>.makeStream()

    let subscription = onPresenceChange {
      continuation.yield($0)
    }

    continuation.onTermination = { _ in
      subscription.cancel()
    }

    return stream
  }

  /// Returns an async stream of ``InsertAction`` values for the given table.
  ///
  /// Register this stream before calling ``subscribeWithError()``.
  ///
  /// - Parameters:
  ///   - type: Pass `InsertAction.self`.
  ///   - schema: The database schema. Defaults to `"public"`.
  ///   - table: The table name, or `nil` to match all tables.
  ///   - filter: An optional ``RealtimePostgresFilter`` to narrow the rows.
  /// - Returns: An `AsyncStream<InsertAction>`.
  @available(
    *, deprecated,
    message: "Use postgresChanges(event:schema:table:filter:select:) instead."
  )
  public func postgresChange(
    _: InsertAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: RealtimePostgresFilter? = nil,
    select: [String]? = nil
  ) -> AsyncStream<InsertAction> {
    postgresChange(
      event: .insert, schema: schema, table: table, filter: filter?.value, select: select
    )
    .compactErase()
  }

  /// Returns an async stream of ``InsertAction`` values for the given table using a raw filter string.
  ///
  /// > Warning: Use the ``RealtimePostgresFilter``-based overload instead.
  @available(
    *,
    deprecated,
    message: "Use the new filter syntax instead."
  )
  @_disfavoredOverload
  public func postgresChange(
    _: InsertAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: String? = nil,
    select: [String]? = nil
  ) -> AsyncStream<InsertAction> {
    postgresChange(event: .insert, schema: schema, table: table, filter: filter, select: select)
      .compactErase()
  }

  /// Returns an async stream of ``UpdateAction`` values for the given table.
  ///
  /// Register this stream before calling ``subscribeWithError()``.
  ///
  /// - Parameters:
  ///   - type: Pass `UpdateAction.self`.
  ///   - schema: The database schema. Defaults to `"public"`.
  ///   - table: The table name, or `nil` to match all tables.
  ///   - filter: An optional ``RealtimePostgresFilter`` to narrow the rows.
  /// - Returns: An `AsyncStream<UpdateAction>`.
  @available(
    *, deprecated,
    message: "Use postgresChanges(event:schema:table:filter:select:) instead."
  )
  public func postgresChange(
    _: UpdateAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: RealtimePostgresFilter? = nil,
    select: [String]? = nil
  ) -> AsyncStream<UpdateAction> {
    postgresChange(
      event: .update, schema: schema, table: table, filter: filter?.value, select: select
    )
    .compactErase()
  }

  /// Returns an async stream of ``UpdateAction`` values for the given table using a raw filter string.
  ///
  /// > Warning: Use the ``RealtimePostgresFilter``-based overload instead.
  @available(
    *,
    deprecated,
    message: "Use the new filter syntax instead."
  )
  @_disfavoredOverload
  public func postgresChange(
    _: UpdateAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: String? = nil,
    select: [String]? = nil
  ) -> AsyncStream<UpdateAction> {
    postgresChange(event: .update, schema: schema, table: table, filter: filter, select: select)
      .compactErase()
  }

  /// Returns an async stream of ``DeleteAction`` values for the given table.
  ///
  /// Register this stream before calling ``subscribeWithError()``.
  ///
  /// - Parameters:
  ///   - type: Pass `DeleteAction.self`.
  ///   - schema: The database schema. Defaults to `"public"`.
  ///   - table: The table name, or `nil` to match all tables.
  ///   - filter: An optional ``RealtimePostgresFilter`` to narrow the rows.
  /// - Returns: An `AsyncStream<DeleteAction>`.
  @available(
    *, deprecated,
    message: "Use postgresChanges(event:schema:table:filter:select:) instead."
  )
  public func postgresChange(
    _: DeleteAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: RealtimePostgresFilter? = nil,
    select: [String]? = nil
  ) -> AsyncStream<DeleteAction> {
    postgresChange(
      event: .delete, schema: schema, table: table, filter: filter?.value, select: select
    )
    .compactErase()
  }

  /// Returns an async stream of ``DeleteAction`` values for the given table using a raw filter string.
  ///
  /// > Warning: Use the ``RealtimePostgresFilter``-based overload instead.
  @available(
    *,
    deprecated,
    message: "Use the new filter syntax instead."
  )
  @_disfavoredOverload
  public func postgresChange(
    _: DeleteAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: String? = nil,
    select: [String]? = nil
  ) -> AsyncStream<DeleteAction> {
    postgresChange(event: .delete, schema: schema, table: table, filter: filter, select: select)
      .compactErase()
  }

  /// Returns an async stream of ``AnyAction`` values for all change types on the given table.
  ///
  /// Register this stream before calling ``subscribeWithError()``.
  ///
  /// - Parameters:
  ///   - type: Pass `AnyAction.self`.
  ///   - schema: The database schema. Defaults to `"public"`.
  ///   - table: The table name, or `nil` to match all tables.
  ///   - filter: An optional ``RealtimePostgresFilter`` to narrow the rows.
  /// - Returns: An `AsyncStream<AnyAction>`.
  @available(
    *, deprecated,
    message: "Use postgresChanges(event:schema:table:filter:select:) instead."
  )
  public func postgresChange(
    _: AnyAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: RealtimePostgresFilter? = nil,
    select: [String]? = nil
  ) -> AsyncStream<AnyAction> {
    postgresChange(
      event: .all, schema: schema, table: table, filter: filter?.value, select: select
    )
  }

  /// Returns an async stream of ``AnyAction`` values using a raw filter string.
  ///
  /// > Warning: Use the ``RealtimePostgresFilter``-based overload instead.
  @available(
    *,
    deprecated,
    message: "Use the new filter syntax instead."
  )
  @_disfavoredOverload
  public func postgresChange(
    _: AnyAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: String? = nil,
    select: [String]? = nil
  ) -> AsyncStream<AnyAction> {
    postgresChange(event: .all, schema: schema, table: table, filter: filter, select: select)
  }

  @available(
    *, deprecated, message: "Use postgresChanges(event:schema:table:filter:select:) instead."
  )
  private func postgresChange(
    event: PostgresChangeEvent,
    schema: String,
    table: String?,
    filter: String?,
    select: [String]? = nil
  ) -> AsyncStream<AnyAction> {
    let (stream, continuation) = AsyncStream<AnyAction>.makeStream()
    let subscription = _onPostgresChange(
      event: event,
      schema: schema,
      table: table,
      filter: filter,
      select: select
    ) {
      continuation.yield($0)
    }
    continuation.onTermination = { _ in
      subscription.cancel()
    }
    return stream
  }

  /// Returns an async stream of the row changes in a table.
  ///
  /// The stream shapes the join request. Open it before you call ``subscribeWithError()``.
  ///
  /// ```swift
  /// let changes = await channel.postgresChanges(table: "messages")
  /// try await channel.subscribeWithError()
  /// for await change in changes {
  ///   if change.kind == .delete {
  ///     print("Deleted", change.oldRecord?["id"] ?? .null)
  ///   }
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - event: The change events to receive. Defaults to ``PostgresChangeEvent/all``.
  ///   - schema: The database schema. Defaults to `"public"`.
  ///   - table: The table name, or `nil` to match all tables.
  ///   - filter: An optional ``RealtimePostgresFilter`` to narrow the rows.
  ///   - select: Restricts the change payload to a subset of columns. Requires an explicit
  ///     `schema` and `table`.
  /// - Returns: An `AsyncStream` of ``PostgresChange`` values.
  ///
  /// > Note: v3 makes a joined channel leave and join again when you open a stream on it. On
  /// > this version a stream opened after the channel started to subscribe reports an issue and
  /// > ends at once.
  public func postgresChanges(
    event: PostgresChangeEvent = .all,
    schema: String = "public",
    table: String? = nil,
    filter: RealtimePostgresFilter? = nil,
    select: [String]? = nil
  ) async -> AsyncStream<PostgresChange> {
    let (stream, continuation) = AsyncStream<PostgresChange>.makeStream()
    let binding = PostgresJoinConfig(
      event: event, schema: schema, table: table, filter: filter?.value, select: select
    )

    let subscription = observePostgresChanges(binding) { [logger] delivery in
      // The server tags a change with every binding it matches, and `*` matches a binding of one
      // event, so a stream for one event can be handed the other statements.
      guard event == .all || event.rawValue == delivery.data.type else { return }
      guard let change = PostgresChange(delivery.data) else {
        logger?.debug("Postgres change without a schema or table: \(delivery.rawMessage)")
        return
      }
      continuation.yield(change)
    }

    guard let subscription else {
      continuation.finish()
      return stream
    }

    continuation.onTermination = { _ in
      subscription.cancel()
    }
    return stream
  }

  /// Returns an async stream of the row changes in a table, bound to a row type.
  ///
  /// The stream does not decode the rows. Call ``TypedPostgresChange/row()`` on each change to
  /// decode its record as `Row`. A row that does not decode never drops the change or ends the
  /// stream; `row()` throws instead.
  ///
  /// The stream shapes the join request. Open it before you call ``subscribeWithError()``.
  ///
  /// ```swift
  /// let changes = await channel.postgresChanges(of: Message.self, table: "messages")
  /// try await channel.subscribeWithError()
  /// for await change in changes where change.kind == .insert {
  ///   let message = try change.row()
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - type: The type to decode each record as.
  ///   - event: The change events to receive. Defaults to ``PostgresChangeEvent/all``.
  ///   - schema: The database schema. Defaults to `"public"`.
  ///   - table: The table name.
  ///   - filter: An optional ``RealtimePostgresFilter`` to narrow the rows.
  ///   - select: Restricts the change payload to a subset of columns.
  ///   - decoder: The decoder ``TypedPostgresChange/row()`` uses. `nil` uses `AnyJSON.decoder`.
  /// - Returns: An `AsyncStream` of ``TypedPostgresChange`` values.
  public func postgresChanges<Row: Decodable>(
    of _: Row.Type,
    event: PostgresChangeEvent = .all,
    schema: String = "public",
    table: String,
    filter: RealtimePostgresFilter? = nil,
    select: [String]? = nil,
    decoder: JSONDecoder? = nil
  ) async -> AsyncStream<TypedPostgresChange<Row>> {
    let changes = await postgresChanges(
      event: event, schema: schema, table: table, filter: filter, select: select
    )
    return AsyncStream(
      TypedPostgresChanges<Row>(
        base: changes, decoder: UncheckedSendable(decoder ?? AnyJSON.decoder)))
  }

  /// Returns an async stream of the broadcast messages for the given event.
  ///
  /// The stream gets JSON messages and binary messages. Read a message with
  /// ``BroadcastMessage/decode(as:decoder:)``, or switch over its ``BroadcastMessage/payload``.
  /// The stream ends when the iterating task is cancelled.
  ///
  /// - Parameter event: The broadcast event name to listen for. Pass `"*"` to receive every
  ///   event.
  /// - Returns: An `AsyncStream` of ``BroadcastMessage`` values.
  ///
  /// > Note: On this version the event name matches without regard to case, as
  /// > ``broadcastStream(event:)`` does. v3 matches it exactly.
  public func broadcasts(event: String) async -> AsyncStream<BroadcastMessage> {
    let (stream, continuation) = AsyncStream<BroadcastMessage>.makeStream()

    let id = callbackManager.addBroadcastMessageCallback(event: event) {
      continuation.yield($0)
    }

    continuation.onTermination = { [weak callbackManager] _ in
      callbackManager?.removeCallback(id: id)
    }

    return stream
  }

  /// Returns an async stream of ``JSONObject`` broadcast payloads for the given event.
  ///
  /// The stream terminates when the caller cancels the enclosing task or the channel is removed.
  ///
  /// - Parameter event: The broadcast event name to listen for.
  /// - Returns: An `AsyncStream<JSONObject>`.
  @available(*, deprecated, message: "Use broadcasts(event:) instead.")
  public func broadcastStream(event: String) -> AsyncStream<JSONObject> {
    let (stream, continuation) = AsyncStream<JSONObject>.makeStream()

    let subscription = onBroadcast(event: event) {
      continuation.yield($0)
    }

    continuation.onTermination = { _ in
      subscription.cancel()
    }

    return stream
  }

  /// Returns an async stream of raw binary `Data` broadcast payloads for the given event.
  ///
  /// Use this when the sender is transmitting binary data via ``RealtimeChannelV2/broadcast(event:data:)``.
  /// Requires protocol ``RealtimeProtocolVersion/v2``.
  ///
  /// - Parameter event: The broadcast event name to listen for.
  /// - Returns: An `AsyncStream<Data>`.
  @available(*, deprecated, message: "Use broadcasts(event:) instead.")
  public func broadcastDataStream(event: String) -> AsyncStream<Data> {
    let (stream, continuation) = AsyncStream<Data>.makeStream()

    let subscription = onBroadcastData(event: event) {
      continuation.yield($0)
    }

    continuation.onTermination = { _ in
      subscription.cancel()
    }

    return stream
  }

  /// Returns an async stream that emits the ``RealtimeMessageV2`` for every `system` event.
  ///
  /// System events convey channel-level status information from the server.
  ///
  /// - Returns: An `AsyncStream<RealtimeMessageV2>`.
  @available(*, deprecated, message: "Use events() instead.")
  public func system() -> AsyncStream<RealtimeMessageV2> {
    let (stream, continuation) = AsyncStream<RealtimeMessageV2>.makeStream()

    let subscription = onSystem {
      continuation.yield($0)
    }

    continuation.onTermination = { _ in
      subscription.cancel()
    }

    return stream
  }

  /// Returns an async stream of ``JSONObject`` broadcast payloads for the given event.
  ///
  /// > Warning: Renamed to ``broadcastStream(event:)``.
  @available(*, deprecated, renamed: "broadcastStream(event:)")
  public func broadcast(event: String) -> AsyncStream<JSONObject> {
    broadcastStream(event: event)
  }
}

// Helper to work around type ambiguity in macOS 13
@available(*, deprecated, message: "Use PostgresChange instead.")
extension AsyncStream<AnyAction> {
  fileprivate func compactErase<T: Sendable>() -> AsyncStream<T> {
    AsyncStream<T>(compactMap { $0.wrappedAction as? T } as AsyncCompactMapSequence<Self, T>)
  }
}

/// Wraps each change of `base` as a ``TypedPostgresChange``.
///
/// A sequence type instead of `map`: the `map` transform would capture `Row.Type`, which is not
/// `Sendable` for every `Row`.
private struct TypedPostgresChanges<Row>: AsyncSequence, Sendable {
  typealias Element = TypedPostgresChange<Row>

  let base: AsyncStream<PostgresChange>
  let decoder: UncheckedSendable<JSONDecoder>

  struct AsyncIterator: AsyncIteratorProtocol {
    var base: AsyncStream<PostgresChange>.Iterator
    let decoder: UncheckedSendable<JSONDecoder>

    mutating func next() async -> TypedPostgresChange<Row>? {
      guard let change = await base.next() else { return nil }
      return TypedPostgresChange(raw: change, decoder: decoder)
    }
  }

  func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(base: base.makeAsyncIterator(), decoder: decoder)
  }
}
