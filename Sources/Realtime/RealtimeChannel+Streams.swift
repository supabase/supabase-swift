//
//  RealtimeChannel+Streams.swift
//
//
//  Created by Guilherme Souza on 17/04/24.
//

import ConcurrencyExtras
public import Foundation

extension RealtimeChannel {
  /// Returns an async stream of the entries that join and leave the channel's presence.
  ///
  /// Each element holds the joins and leaves of one sync, by presence key. The first sync after
  /// ``subscribe()`` reports every present client as a join. After a rejoin, the stream reports
  /// only the clients that joined or left while the channel was away. ``unsubscribe()`` reports
  /// every client as a leave, so the changes always add up to ``presenceState``. A sync that
  /// changes nothing emits nothing.
  ///
  /// Having a presence stream open when ``subscribe()`` runs is what enables presence on the
  /// channel, so open it before subscribing. Opening one after ``subscribe()`` reports an issue
  /// and returns a stream that ends at once. The stream ends when the iterating task is
  /// cancelled or the channel is removed.
  ///
  /// - Returns: An `AsyncStream` of ``PresenceChange`` values.
  public func presenceChanges() async -> AsyncStream<PresenceChange> {
    await client?.presenceChanges(of: self) ?? .finished
  }

  /// Returns an async stream of the channel's presence state.
  ///
  /// The stream emits ``presenceState`` at once, then the new state after every presence sync
  /// that changes it.
  ///
  /// Having a presence stream open when ``subscribe()`` runs is what enables presence on the
  /// channel, so open it before subscribing. Opening one after ``subscribe()`` reports an issue
  /// and returns a stream that ends at once. The stream ends when the iterating task is
  /// cancelled or the channel is removed.
  ///
  /// - Returns: An `AsyncStream` of ``PresenceState`` values.
  public func presenceStates() async -> AsyncStream<PresenceState> {
    await client?.presenceStates(of: self) ?? .finished
  }

  /// Returns an async stream of the row changes in a table.
  ///
  /// The stream shapes the join request. Open it before you call ``subscribe()``: a stream
  /// opened on a joined channel makes the channel leave and join again with the new binding.
  ///
  /// ```swift
  /// let changes = await channel.postgresChanges(table: "messages")
  /// try await channel.subscribe()
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
  public func postgresChanges(
    event: PostgresChangeEvent = .all,
    schema: String = "public",
    table: String? = nil,
    filter: RealtimePostgresFilter? = nil,
    select: [String]? = nil
  ) async -> AsyncStream<PostgresChange> {
    await postgresChanges(
      event: event, schema: schema, table: table, filter: filter?.value, select: select
    )
  }

  /// Returns an async stream of the row changes in a table, bound to a row type.
  ///
  /// The stream does not decode the rows. Call ``TypedPostgresChange/row()`` on each change to
  /// decode its record as `Row`. A row that does not decode never drops the change or ends the
  /// stream; `row()` throws instead.
  ///
  /// The stream shapes the join request. Open it before you call ``subscribe()``: a stream
  /// opened on a joined channel makes the channel leave and join again with the new binding.
  ///
  /// The method runs on the caller's actor, so `Row` can have a `Decodable` conformance isolated
  /// to the main actor. Only the binding crosses to the client.
  ///
  /// ```swift
  /// let changes = await channel.postgresChanges(of: Message.self, table: "messages")
  /// try await channel.subscribe()
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
  ///   - decoder: The decoder ``TypedPostgresChange/row()`` uses. Defaults to the decoder the SDK
  ///     uses for server responses.
  /// - Returns: An `AsyncStream` of ``TypedPostgresChange`` values.
  public func postgresChanges<Row: Decodable>(
    of _: Row.Type,
    event: PostgresChangeEvent = .all,
    schema: String = "public",
    table: String,
    filter: RealtimePostgresFilter? = nil,
    select: [String]? = nil,
    decoder: JSONDecoder = .supabase()
  ) async -> AsyncStream<TypedPostgresChange<Row>> {
    await postgresChanges(
      of: Row.self, event: event, schema: schema, table: table, rawFilter: filter?.value,
      select: select, decoder: decoder
    )
  }

  /// The typed stream for a filter already in the `postgres_changes` grammar, for the `Supabase`
  /// module, which renders it from a typed PostgREST filter.
  package func postgresChanges<Row: Decodable>(
    of _: Row.Type,
    event: PostgresChangeEvent,
    schema: String,
    table: String,
    rawFilter: String?,
    select: [String]?,
    decoder: JSONDecoder
  ) async -> AsyncStream<TypedPostgresChange<Row>> {
    let changes = await postgresChanges(
      event: event, schema: schema, table: table, filter: rawFilter, select: select
    )
    return AsyncStream(
      TypedPostgresChanges<Row>(base: changes, decoder: UncheckedSendable(decoder)))
  }

  /// One stream of the changes for `bindings`, the channel events, and the status changes, in
  /// the order the channel received them.
  ///
  /// Separate streams lose that order across each other. A live query needs it: a change
  /// delivered before ``RealtimeChannelEvent/resubscribed`` is older than the data fetched after
  /// it, and must not be applied on top of that data.
  ///
  /// A change that matches more than one of `bindings` is delivered once.
  package func postgresChangesSignals(
    bindings: [PostgresJoinConfig]
  ) async -> AsyncStream<PostgresChangesSignal> {
    await client?.postgresChangesSignals(of: self, bindings) ?? .finished
  }

  func postgresChanges(
    event: PostgresChangeEvent,
    schema: String,
    table: String?,
    filter: String?,
    select: [String]?
  ) async -> AsyncStream<PostgresChange> {
    let config = PostgresJoinConfig(
      event: event,
      schema: schema,
      table: table,
      filter: filter,
      select: select
    )
    return await client?.postgresChanges(of: self, config) ?? .finished
  }

  /// Returns an async stream of the broadcast messages for the given event.
  ///
  /// The stream gets JSON messages and binary messages. Read a message with
  /// ``BroadcastMessage/decode(as:decoder:)``, or switch over its ``BroadcastMessage/payload``.
  /// The stream ends when the iterating task is cancelled or the channel is removed.
  ///
  /// - Parameter event: The broadcast event name to listen for. Pass `"*"` to receive every
  ///   event.
  /// - Returns: An `AsyncStream` of ``BroadcastMessage`` values.
  public func broadcasts(event: String) async -> AsyncStream<BroadcastMessage> {
    await client?.broadcasts(of: self, event: event) ?? .finished
  }

  /// Returns an async stream of server events about this channel.
  ///
  /// The stream emits ``RealtimeChannelEvent/resubscribed`` when the channel joins again after
  /// a reconnect or a rejoin, and reports whether the server set up the channel's Postgres
  /// changes subscriptions. Cancelling the iterating task ends the stream; so does removing the
  /// channel from its client.
  ///
  /// ```swift
  /// for await event in await channel.events() {
  ///   if event == .resubscribed {
  ///     await reloadMessages()
  ///   }
  /// }
  /// ```
  public func events() async -> AsyncStream<RealtimeChannelEvent> {
    await client?.events(of: self) ?? .finished
  }
}

/// Wraps each change of `base` as a ``TypedPostgresChange``.
///
/// A sequence type instead of `map`: the `map` transform runs off the caller's actor and would
/// capture `Row.Type`, whose `Decodable` conformance may be isolated to the caller's actor.
private struct TypedPostgresChanges<Row>: AsyncSequence, Sendable {
  let base: AsyncStream<PostgresChange>
  let decoder: UncheckedSendable<JSONDecoder>

  struct AsyncIterator: AsyncIteratorProtocol {
    var base: AsyncStream<PostgresChange>.Iterator
    let decoder: UncheckedSendable<JSONDecoder>

    @concurrent mutating func next() async -> TypedPostgresChange<Row>? {
      guard let change = await base.next() else { return nil }
      return TypedPostgresChange(raw: change, decoder: decoder)
    }
  }

  func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(base: base.makeAsyncIterator(), decoder: decoder)
  }
}
