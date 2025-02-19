//
//  RealtimeChannel+AsyncAwait.swift
//
//
//  Created by Guilherme Souza on 17/04/24.
//

import Foundation

public enum RealtimeFilter {
  case eq(_ column: String, value: any RealtimeFilterValue)
  case neq(_ column: String, value: any RealtimeFilterValue)
  case gt(_ column: String, value: any RealtimeFilterValue)
  case gte(_ column: String, value: any RealtimeFilterValue)
  case lt(_ column: String, value: any RealtimeFilterValue)
  case lte(_ column: String, value: any RealtimeFilterValue)
  case `in`(_ column: String, values: [any RealtimeFilterValue])

  var value: String {
    switch self {
    case let .eq(column, value):
      return "\(column)=eq.\(value.rawValue)"
    case let .neq(column, value):
      return "\(column)=neq.\(value.rawValue)"
    case let .gt(column, value):
      return "\(column)=gt.\(value.rawValue)"
    case let .gte(column, value):
      return "\(column)=gte.\(value.rawValue)"
    case let .lt(column, value):
      return "\(column)=lt.\(value.rawValue)"
    case let .lte(column, value):
      return "\(column)=lte.\(value.rawValue)"
    case let .in(column, values):
      return "\(column)=in.(\(values.map(\.rawValue)))"
    }
  }
}

extension RealtimeChannelV2 {
  /// Listen for clients joining / leaving the channel using presences.
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

  /// Listen for postgres changes in a channel.
  public func postgresChange(
    _: InsertAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: RealtimeFilter? = nil
  ) -> AsyncStream<InsertAction> {
    postgresChange(event: .insert, schema: schema, table: table, filter: filter?.value)
      .compactErase()
  }

  /// Listen for postgres changes in a channel.
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
    filter: String? = nil
  ) -> AsyncStream<InsertAction> {
    postgresChange(event: .insert, schema: schema, table: table, filter: filter)
      .compactErase()
  }

  /// Listen for postgres changes in a channel.
  public func postgresChange(
    _: UpdateAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: RealtimeFilter? = nil
  ) -> AsyncStream<UpdateAction> {
    postgresChange(event: .update, schema: schema, table: table, filter: filter?.value)
      .compactErase()
  }

  /// Listen for postgres changes in a channel.
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
    filter: String? = nil
  ) -> AsyncStream<UpdateAction> {
    postgresChange(event: .update, schema: schema, table: table, filter: filter)
      .compactErase()
  }

  /// Listen for postgres changes in a channel.
  public func postgresChange(
    _: DeleteAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: RealtimeFilter? = nil
  ) -> AsyncStream<DeleteAction> {
    postgresChange(event: .delete, schema: schema, table: table, filter: filter?.value)
      .compactErase()
  }

  /// Listen for postgres changes in a channel.
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
    filter: String? = nil
  ) -> AsyncStream<DeleteAction> {
    postgresChange(event: .delete, schema: schema, table: table, filter: filter)
      .compactErase()
  }

  /// Listen for postgres changes in a channel.
  public func postgresChange(
    _: AnyAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: RealtimeFilter? = nil
  ) -> AsyncStream<AnyAction> {
    postgresChange(event: .all, schema: schema, table: table, filter: filter?.value)
  }

  /// Listen for postgres changes in a channel.
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
    filter: String? = nil
  ) -> AsyncStream<AnyAction> {
    postgresChange(event: .all, schema: schema, table: table, filter: filter)
  }

  private func postgresChange(
    event: PostgresChangeEvent,
    schema: String,
    table: String?,
    filter: String?
  ) -> AsyncStream<AnyAction> {
    let (stream, continuation) = AsyncStream<AnyAction>.makeStream()
    let subscription = _onPostgresChange(
      event: event,
      schema: schema,
      table: table,
      filter: filter
    ) {
      continuation.yield($0)
    }
    continuation.onTermination = { _ in
      subscription.cancel()
    }
    return stream
  }

  /// Listen for broadcast messages sent by other clients within the same channel under a specific `event`.
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
  
  /// Listen for `system` event.
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

  /// Listen for broadcast messages sent by other clients within the same channel under a specific `event`.
  @available(*, deprecated, renamed: "broadcastStream(event:)")
  public func broadcast(event: String) -> AsyncStream<JSONObject> {
    broadcastStream(event: event)
  }
}

// Helper to work around type ambiguity in macOS 13
fileprivate extension AsyncStream<AnyAction> {
  func compactErase<T: Sendable>() -> AsyncStream<T> {
    AsyncStream<T>(compactMap { $0.wrappedAction as? T } as AsyncCompactMapSequence<Self, T>)
  }
}
