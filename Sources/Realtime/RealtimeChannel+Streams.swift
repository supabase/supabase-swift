//
//  RealtimeChannel+Streams.swift
//
//
//  Created by Guilherme Souza on 17/04/24.
//

import ConcurrencyExtras
public import Foundation
import IssueReporting

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
  /// channel, so open it before subscribing. The stream ends when the iterating task is
  /// cancelled or the channel is removed.
  ///
  /// - Returns: An `AsyncStream` of ``PresenceChange`` values.
  public func presenceChanges() -> AsyncStream<PresenceChange> {
    guard canChangeJoinConfig(for: "presence") else { return .finished }
    let (stream, continuation) = AsyncStream<PresenceChange>.makeStream(
      bufferingPolicy: .unbounded
    )
    register(.presence(continuation), terminating: continuation)
    return stream
  }

  /// Returns an async stream of the channel's presence state.
  ///
  /// The stream emits ``presenceState`` at once, then the new state after every presence sync
  /// that changes it.
  ///
  /// Having a presence stream open when ``subscribe()`` runs is what enables presence on the
  /// channel, so open it before subscribing. The stream ends when the iterating task is
  /// cancelled or the channel is removed.
  ///
  /// - Returns: An `AsyncStream` of ``PresenceState`` values.
  public func presenceStates() -> AsyncStream<PresenceState> {
    guard canChangeJoinConfig(for: "presence") else { return .finished }
    let (stream, continuation) = AsyncStream<PresenceState>.makeStream(
      bufferingPolicy: .unbounded
    )
    register(.presenceState(continuation), terminating: continuation)
    continuation.yield(presenceState)
    return stream
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
  ) -> AsyncStream<PostgresChange> {
    postgresChanges(
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
  /// to the main actor.
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
  nonisolated public func postgresChanges<Row: Decodable>(
    of _: Row.Type,
    event: PostgresChangeEvent = .all,
    schema: String = "public",
    table: String,
    filter: RealtimePostgresFilter? = nil,
    select: [String]? = nil,
    decoder: JSONDecoder = .supabase()
  ) async -> AsyncStream<TypedPostgresChange<Row>> {
    let decoder = UncheckedSendable(decoder)
    let changes = await postgresChanges(
      event: event, schema: schema, table: table, filter: filter?.value, select: select
    )
    return AsyncStream(changes.map { TypedPostgresChange(raw: $0, decoder: decoder) })
  }

  func postgresChanges(
    event: PostgresChangeEvent,
    schema: String,
    table: String?,
    filter: String?,
    select: [String]?
  ) -> AsyncStream<PostgresChange> {
    let config = PostgresJoinConfig(
      event: event,
      schema: schema,
      table: table,
      filter: filter,
      select: select
    )

    let (stream, continuation) = AsyncStream<PostgresChange>.makeStream(
      bufferingPolicy: .unbounded
    )
    register(.postgres(config, continuation), terminating: continuation)
    rejoinIfBindingsChanged()
    return stream
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
  public func broadcasts(event: String) -> AsyncStream<BroadcastMessage> {
    let (stream, continuation) = AsyncStream<BroadcastMessage>.makeStream(
      bufferingPolicy: .unbounded
    )
    register(.broadcast(event: event, continuation), terminating: continuation)
    return stream
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
  public func events() -> AsyncStream<RealtimeChannelEvent> {
    let (stream, continuation) = AsyncStream<RealtimeChannelEvent>.makeStream(
      bufferingPolicy: .unbounded
    )
    register(.events(continuation), terminating: continuation)
    return stream
  }

  /// Presence streams shape the join payload, so they can only be opened before the join is sent.
  private func canChangeJoinConfig(for feature: String) -> Bool {
    switch state {
    case .unsubscribed, .unsubscribing, .failed:
      return true
    case .subscribing, .subscribed:
      reportIssue(
        """
        Cannot open "\(feature)" streams for "\(topic)" after `subscribe()`.
        Please open all your \(feature) streams before subscribing to the channel.
        """
      )
      return false
    }
  }
}

extension AsyncStream {
  /// A stream with no elements.
  fileprivate static var finished: AsyncStream {
    AsyncStream { $0.finish() }
  }
}
