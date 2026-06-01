//
//  Channel+Postgres.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/25.
//

import Foundation

extension Channel {
  // MARK: - Typed streams

  public func changes<T: Decodable & Sendable & RealtimeTable>(
    to _: T.Type = T.self,
    where filter: Filter<T>? = nil,
    decoder: JSONDecoder = JSONDecoder()
  ) -> AsyncThrowingStream<PostgresChange<T>, any Error> {
    let subscriptionId = UUID()
    return AsyncThrowingStream { continuation in
      let id = UUID()
      Task {
        await self.registerPostgresHandler(id: id) { payload in
          do {
            let change = try PostgresChange<T>.decode(from: payload)
            continuation.yield(change)
          } catch {
            continuation.finish(
              throwing: RealtimeError.decoding(type: String(describing: T.self), underlying: error)
            )
          }
        } finish: {
          continuation.finish()
        }
        continuation.onTermination = { [id] _ in
          Task { await self.unregisterPostgresHandlers(id: id) }
        }
        do {
          try await self.joinWithPostgresFilter(
            schema: T.schema, table: T.tableName,
            filter: filter?.wireValue,
            subscriptionId: subscriptionId
          )
        } catch let e as RealtimeError {
          continuation.finish(throwing: e)
        }
      }
    }
  }

  public func inserts<T: Decodable & Sendable & RealtimeTable>(
    into _: T.Type = T.self,
    where filter: Filter<T>? = nil
  ) -> AsyncThrowingStream<T, any Error> {
    let raw = changes(to: T.self, where: filter)
    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await change in raw {
            if case .insert(let row) = change { continuation.yield(row) }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  public func updates<T: Decodable & Sendable & RealtimeTable>(
    of _: T.Type = T.self,
    where filter: Filter<T>? = nil
  ) -> AsyncThrowingStream<(old: T, new: T), any Error> {
    let raw = changes(to: T.self, where: filter)
    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await change in raw {
            if case .update(let old, let new) = change { continuation.yield((old, new)) }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  public func deletes<T: Decodable & Sendable & RealtimeTable>(
    from _: T.Type = T.self,
    where filter: Filter<T>? = nil
  ) -> AsyncThrowingStream<T, any Error> {
    let raw = changes(to: T.self, where: filter)
    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await change in raw {
            if case .delete(let old) = change { continuation.yield(old) }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  // MARK: - Untyped escape hatch

  public func changes(
    schema: String = "public",
    table: String,
    filter: UntypedFilter? = nil
  ) -> AsyncThrowingStream<PostgresChange<[String: JSONValue]>, any Error> {
    let subscriptionId = UUID()
    return AsyncThrowingStream { continuation in
      let id = UUID()
      Task {
        await self.registerPostgresHandler(id: id) { payload in
          do {
            let change = try PostgresChange<[String: JSONValue]>.decode(from: payload)
            continuation.yield(change)
          } catch {
            continuation.finish(
              throwing: RealtimeError.decoding(
                type: "[String: JSONValue]", underlying: error)
            )
          }
        } finish: {
          continuation.finish()
        }
        continuation.onTermination = { [id] _ in
          Task { await self.unregisterPostgresHandlers(id: id) }
        }
        do {
          try await self.joinWithPostgresFilter(
            schema: schema, table: table,
            filter: filter?.wireValue,
            subscriptionId: subscriptionId
          )
        } catch let e as RealtimeError {
          continuation.finish(throwing: e)
        }
      }
    }
  }

  // MARK: - Internal registration helpers

  func registerPostgresHandler(
    id: UUID,
    onPayload: @escaping @Sendable ([String: JSONValue]) -> Void,
    finish: @escaping @Sendable () -> Void
  ) {
    postgresHandlers[id] = onPayload
    postgresFinishHandlers[id] = finish
  }

  func unregisterPostgresHandlers(id: UUID) {
    postgresHandlers.removeValue(forKey: id)
    postgresFinishHandlers.removeValue(forKey: id)
  }

  private func joinWithPostgresFilter(
    schema: String, table: String,
    filter: String?, subscriptionId: UUID
  ) async throws(RealtimeError) {
    _postgresSubscriptions[subscriptionId] = PostgresSubscription(
      id: subscriptionId, schema: schema, table: table, filter: filter
    )
    try await joinIfNeeded()
  }
}
