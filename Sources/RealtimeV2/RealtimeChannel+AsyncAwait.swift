//
//  RealtimeChannel+AsyncAwait.swift
//
//
//  Created by Guilherme Souza on 17/04/24.
//

import ConcurrencyExtras
public import Foundation

extension RealtimeChannelV2 {
  /// Returns an async stream that emits a ``PresenceAction`` whenever clients join or leave.
  ///
  /// The stream terminates when the caller cancels the enclosing task or the channel is removed.
  /// Register this stream before calling ``subscribeWithError()``.
  ///
  /// - Returns: An `AsyncStream` of ``PresenceAction`` values.
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

  /// Returns an async stream of ``JSONObject`` broadcast payloads for the given event.
  ///
  /// The stream terminates when the caller cancels the enclosing task or the channel is removed.
  ///
  /// - Parameter event: The broadcast event name to listen for.
  /// - Returns: An `AsyncStream<JSONObject>`.
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
extension AsyncStream<AnyAction> {
  fileprivate func compactErase<T: Sendable>() -> AsyncStream<T> {
    AsyncStream<T>(compactMap { $0.wrappedAction as? T } as AsyncCompactMapSequence<Self, T>)
  }
}
