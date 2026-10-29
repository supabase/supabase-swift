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
  /// only the clients that joined or left while the channel was away.
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
  /// The stream emits ``presenceState`` at once, then the new state after every presence sync.
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

  /// Returns an async stream of ``InsertAction`` values for the given table.
  ///
  /// Open this stream before calling ``subscribe()``; it shapes the join request.
  ///
  /// - Parameters:
  ///   - type: Pass `InsertAction.self`.
  ///   - schema: The database schema. Defaults to `"public"`.
  ///   - table: The table name, or `nil` to match all tables.
  ///   - filter: An optional ``RealtimePostgresFilter`` to narrow the rows.
  ///   - select: Restricts the change payload to a subset of columns. Requires an explicit
  ///     `schema` and `table`.
  /// - Returns: An `AsyncStream<InsertAction>`.
  public func postgresChanges(
    _: InsertAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: RealtimePostgresFilter? = nil,
    select: [String]? = nil
  ) -> AsyncStream<InsertAction> {
    postgresChanges(
      event: .insert, schema: schema, table: table, filter: filter?.value, select: select
    )
    .compactErase()
  }

  /// Returns an async stream of ``UpdateAction`` values for the given table.
  ///
  /// Open this stream before calling ``subscribe()``; it shapes the join request.
  ///
  /// - Parameters:
  ///   - type: Pass `UpdateAction.self`.
  ///   - schema: The database schema. Defaults to `"public"`.
  ///   - table: The table name, or `nil` to match all tables.
  ///   - filter: An optional ``RealtimePostgresFilter`` to narrow the rows.
  ///   - select: Restricts the change payload to a subset of columns. Requires an explicit
  ///     `schema` and `table`.
  /// - Returns: An `AsyncStream<UpdateAction>`.
  public func postgresChanges(
    _: UpdateAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: RealtimePostgresFilter? = nil,
    select: [String]? = nil
  ) -> AsyncStream<UpdateAction> {
    postgresChanges(
      event: .update, schema: schema, table: table, filter: filter?.value, select: select
    )
    .compactErase()
  }

  /// Returns an async stream of ``DeleteAction`` values for the given table.
  ///
  /// Open this stream before calling ``subscribe()``; it shapes the join request.
  ///
  /// - Parameters:
  ///   - type: Pass `DeleteAction.self`.
  ///   - schema: The database schema. Defaults to `"public"`.
  ///   - table: The table name, or `nil` to match all tables.
  ///   - filter: An optional ``RealtimePostgresFilter`` to narrow the rows.
  ///   - select: Restricts the change payload to a subset of columns. Requires an explicit
  ///     `schema` and `table`.
  /// - Returns: An `AsyncStream<DeleteAction>`.
  public func postgresChanges(
    _: DeleteAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: RealtimePostgresFilter? = nil,
    select: [String]? = nil
  ) -> AsyncStream<DeleteAction> {
    postgresChanges(
      event: .delete, schema: schema, table: table, filter: filter?.value, select: select
    )
    .compactErase()
  }

  /// Returns an async stream of ``AnyAction`` values for all change types on the given table.
  ///
  /// Open this stream before calling ``subscribe()``; it shapes the join request.
  ///
  /// - Parameters:
  ///   - type: Pass `AnyAction.self`.
  ///   - schema: The database schema. Defaults to `"public"`.
  ///   - table: The table name, or `nil` to match all tables.
  ///   - filter: An optional ``RealtimePostgresFilter`` to narrow the rows.
  ///   - select: Restricts the change payload to a subset of columns. Requires an explicit
  ///     `schema` and `table`.
  /// - Returns: An `AsyncStream<AnyAction>`.
  public func postgresChanges(
    _: AnyAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: RealtimePostgresFilter? = nil,
    select: [String]? = nil
  ) -> AsyncStream<AnyAction> {
    postgresChanges(
      event: .all, schema: schema, table: table, filter: filter?.value, select: select
    )
  }

  func postgresChanges(
    event: PostgresChangeEvent,
    schema: String,
    table: String?,
    filter: String?,
    select: [String]? = nil
  ) -> AsyncStream<AnyAction> {
    guard canChangeJoinConfig(for: "postgres_changes") else { return .finished }

    let config = PostgresJoinConfig(
      event: event,
      schema: schema,
      table: table,
      filter: filter,
      select: select
    )

    let (stream, continuation) = AsyncStream<AnyAction>.makeStream(bufferingPolicy: .unbounded)
    register(.postgres(config, continuation), terminating: continuation)
    return stream
  }

  /// Returns an async stream of ``JSONObject`` broadcast payloads for the given event.
  ///
  /// The stream ends when the iterating task is cancelled or the channel is removed. Pass `"*"`
  /// to receive every event.
  ///
  /// - Parameter event: The broadcast event name to listen for.
  /// - Returns: An `AsyncStream<JSONObject>`.
  public func broadcasts(event: String) -> AsyncStream<JSONObject> {
    let (stream, continuation) = AsyncStream<JSONObject>.makeStream(bufferingPolicy: .unbounded)
    register(.broadcast(event: event, continuation), terminating: continuation)
    return stream
  }

  /// Returns an async stream of raw binary `Data` broadcast payloads for the given event.
  ///
  /// Use this when the sender is transmitting binary data via ``broadcast(event:data:)``.
  ///
  /// - Parameter event: The broadcast event name to listen for.
  /// - Returns: An `AsyncStream<Data>`.
  public func broadcastData(event: String) -> AsyncStream<Data> {
    let (stream, continuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .unbounded)
    register(.broadcastData(event: event, continuation), terminating: continuation)
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

  /// Streams that shape the join payload can only be opened before the join is sent.
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

extension AsyncStream<AnyAction> {
  fileprivate func compactErase<T: Sendable>() -> AsyncStream<T> {
    AsyncStream<T>(compactMap { $0.wrappedAction as? T } as AsyncCompactMapSequence<Self, T>)
  }
}

extension AsyncStream {
  /// A stream with no elements.
  fileprivate static var finished: AsyncStream {
    AsyncStream { $0.finish() }
  }
}
