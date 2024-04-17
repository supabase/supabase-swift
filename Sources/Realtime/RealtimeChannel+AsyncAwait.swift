//
//  RealtimeChannel+AsyncAwait.swift
//
//
//  Created by Guilherme Souza on 17/04/24.
//

import Foundation

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
    filter: String? = nil
  ) -> AsyncStream<InsertAction> {
    postgresChange(event: .insert, schema: schema, table: table, filter: filter)
      .compactMap { $0.wrappedAction as? InsertAction }
      .eraseToStream()
  }

  /// Listen for postgres changes in a channel.
  public func postgresChange(
    _: UpdateAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: String? = nil
  ) -> AsyncStream<UpdateAction> {
    postgresChange(event: .update, schema: schema, table: table, filter: filter)
      .compactMap { $0.wrappedAction as? UpdateAction }
      .eraseToStream()
  }

  /// Listen for postgres changes in a channel.
  public func postgresChange(
    _: DeleteAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: String? = nil
  ) -> AsyncStream<DeleteAction> {
    postgresChange(event: .delete, schema: schema, table: table, filter: filter)
      .compactMap { $0.wrappedAction as? DeleteAction }
      .eraseToStream()
  }

  /// Listen for postgres changes in a channel.
  public func postgresChange(
    _: SelectAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: String? = nil
  ) -> AsyncStream<SelectAction> {
    postgresChange(event: .select, schema: schema, table: table, filter: filter)
      .compactMap { $0.wrappedAction as? SelectAction }
      .eraseToStream()
  }

  /// Listen for postgres changes in a channel.
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
}
