//
//  RealtimeChannel+AsyncAwait.swift
//
//
//  Created by Guilherme Souza on 17/04/24.
//

import Foundation
import PostgREST

public enum RealtimeChannelV2Filter {
  case eq(column: String, value: any URLQueryRepresentable)
  case neq(column: String, value: any URLQueryRepresentable)
  case gt(column: String, value: any URLQueryRepresentable)
  case gte(column: String, value: any URLQueryRepresentable)
  case lt(column: String, value: any URLQueryRepresentable)
  case lte(column: String, value: any URLQueryRepresentable)
  case `in`(column: String, values: [any URLQueryRepresentable])

  var value: String {
    switch self {
    case let .eq(column, value):
      return "\(column)=eq.\(value.queryValue)"
    case let .neq(column, value):
      return "\(column)=neq.\(value.queryValue)"
    case let .gt(column, value):
      return "\(column)=gt.\(value.queryValue)"
    case let .gte(column, value):
      return "\(column)=gte.\(value.queryValue)"
    case let .lt(column, value):
      return "\(column)=lt.\(value.queryValue)"
    case let .lte(column, value):
      return "\(column)=lte.\(value.queryValue)"
    case let .in(column, values):
      return "\(column)=in.(\(values.map(\.queryValue).joined(separator: ",")))"
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
    filter: RealtimeChannelV2Filter? = nil
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
    filter: RealtimeChannelV2Filter? = nil
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
    filter: RealtimeChannelV2Filter? = nil
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
    filter: RealtimeChannelV2Filter? = nil
  ) -> AsyncStream<AnyAction> {
    postgresChange(event: .all, schema: schema, table: table, filter: filter?.value)
  }

  /// Listen for postgres changes in a channel.
  @available(
    *,
     deprecated,
     message: "Use the new filter syntax instead."
  )
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
