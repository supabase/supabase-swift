//
//  LiveQueryEngine.swift
//  Supabase
//
//  Created by Guilherme Souza on 30/10/26.
//

import Foundation
import Helpers
import Realtime

/// A row of a live query with its primary key values, in primary key column order.
struct LiveRow<R> {
  var key: [JSONValue]
  var row: R
}

extension LiveRow: Sendable where R: Sendable {}

/// What a live query reports.
enum LiveQueryUpdate<R> {
  /// The full current result set. The query is live.
  case rows([R])
  /// The rows may be out of date: the channel is away, or a fetch is running.
  case stale
}

extension LiveQueryUpdate: Sendable where R: Sendable {}
extension LiveQueryUpdate: Equatable where R: Equatable {}

/// The rules of a live query, without the channel or the fetch.
///
/// Changes that arrive while a fetch runs wait in a buffer and apply on top of its rows. A change
/// older, by `commit_timestamp`, than the last one applied to its row is skipped.
struct LiveQueryMachine<R> {
  enum Input {
    case change(PostgresChange)
    case resubscribed
    case status(RealtimeChannelStatus)
    case fetched(generation: Int, [LiveRow<R>])
    case fetchFailed(generation: Int, any Error)
  }

  enum Effect {
    case fetch(generation: Int)
    case emit(LiveQueryUpdate<R>)
  }

  private let primaryKey: [String]
  private let decode: (PostgresRow) throws -> R

  private var rows: [LiveRow<R>] = []
  private var lastCommit: [[JSONValue]: Date] = [:]
  private var generation = 0
  private var buffer: [PostgresChange] = []
  private var isFetching = false
  private var isSubscribed = true

  init(primaryKey: [String], decode: @escaping (PostgresRow) throws -> R) {
    self.primaryKey = primaryKey
    self.decode = decode
  }

  mutating func start() -> [Effect] {
    [fetch()]
  }

  mutating func handle(_ input: Input) throws -> [Effect] {
    switch input {
    case .change(let change):
      if isFetching {
        buffer.append(change)
        return []
      }
      return try apply(change) ? [emitRows()] : []

    case .resubscribed:
      buffer = []
      return [.emit(.stale), fetch()]

    case .status(.failed(let error)):
      throw error

    case .status(let status):
      isSubscribed = status.isSubscribed
      return isSubscribed || isFetching ? [] : [.emit(.stale)]

    case .fetched(let fetchGeneration, let fetched):
      guard fetchGeneration == generation else { return [] }
      rows = fetched
      isFetching = false
      let buffered = buffer
      buffer = []
      for change in buffered {
        _ = try apply(change)
      }
      return isSubscribed ? [emitRows()] : [emitRows(), .emit(.stale)]

    case .fetchFailed(let fetchGeneration, let error):
      guard fetchGeneration == generation else { return [] }
      throw error
    }
  }

  private mutating func fetch() -> Effect {
    generation += 1
    isFetching = true
    return .fetch(generation: generation)
  }

  private func emitRows() -> Effect {
    .emit(.rows(rows.map(\.row)))
  }

  /// Applies a change by primary key. Returns whether the rows changed.
  private mutating func apply(_ change: PostgresChange) throws -> Bool {
    let isDelete = change.kind == .delete
    guard isDelete || change.kind == .insert || change.kind == .update,
      let source = isDelete ? change.oldRecord : change.record
    else { return false }

    let key = primaryKey.map { source[$0] ?? .null }
    if let last = lastCommit[key], change.commitTimestamp < last {
      return false
    }
    lastCommit[key] = change.commitTimestamp

    let index = rows.firstIndex { $0.key == key }
    if isDelete {
      guard let index else { return false }
      rows.remove(at: index)
      return true
    }

    let row = LiveRow(key: key, row: try decode(source))
    if let index {
      rows[index] = row
    } else {
      rows.append(row)
    }
    return true
  }
}

extension LiveQueryMachine.Input: Sendable where R: Sendable {}
extension LiveQueryMachine.Effect: Equatable where R: Equatable {}

/// What a live query runs against: one dedicated channel and a way to fetch the rows.
struct LiveQuerySource<R: Sendable>: Sendable {
  /// The channel's changes, events and status changes, in order. Opened before ``subscribe``.
  var signals: AsyncStream<PostgresChangesSignal>
  var primaryKey: [String]
  var decode: @Sendable (PostgresRow) throws -> R
  /// Joins the channel. Returns once the server reports the Postgres changes live.
  var subscribe: @Sendable () async throws -> Void
  var fetch: @Sendable () async throws -> [LiveRow<R>]
  /// Removes the channel.
  var finish: @Sendable () async -> Void
}

/// Runs a live query: subscribes, fetches, then applies changes until the iteration ends or the
/// query fails. The channel is removed either way.
func makeLiveQueryUpdates<R: Sendable>(
  _ makeSource: @escaping @Sendable () async -> LiveQuerySource<R>
) -> AsyncThrowingStream<LiveQueryUpdate<R>, any Error> {
  let (updates, output) = AsyncThrowingStream<LiveQueryUpdate<R>, any Error>.makeStream()
  let task = Task {
    let source = await makeSource()
    do {
      try await runLiveQuery(source, output: output)
      output.finish()
    } catch {
      output.finish(throwing: error)
    }
    // An unstructured task, so the removal still runs when the iteration was cancelled.
    await Task { await source.finish() }.value
  }
  output.onTermination = { _ in task.cancel() }
  return updates
}

private func runLiveQuery<R: Sendable>(
  _ source: LiveQuerySource<R>,
  output: AsyncThrowingStream<LiveQueryUpdate<R>, any Error>.Continuation
) async throws {
  typealias Input = LiveQueryMachine<R>.Input
  let (inputs, input) = AsyncStream<Input>.makeStream()

  // One forwarder keeps the channel's order. Fetch results join the same stream.
  let forwarder = Task {
    for await signal in source.signals {
      switch signal {
      case .change(let change): input.yield(.change(change))
      case .event(.resubscribed): input.yield(.resubscribed)
      case .event: break
      case .status(let status): input.yield(.status(status))
      }
    }
    input.finish()
  }
  var fetchTask: Task<Void, Never>?
  defer {
    forwarder.cancel()
    fetchTask?.cancel()
  }

  try await source.subscribe()

  var machine = LiveQueryMachine<R>(primaryKey: source.primaryKey, decode: source.decode)
  func perform(_ effects: [LiveQueryMachine<R>.Effect]) {
    for effect in effects {
      switch effect {
      case .emit(let update):
        output.yield(update)
      case .fetch(let generation):
        fetchTask?.cancel()
        fetchTask = Task {
          do {
            input.yield(.fetched(generation: generation, try await source.fetch()))
          } catch {
            input.yield(.fetchFailed(generation: generation, error))
          }
        }
      }
    }
  }

  perform(machine.start())
  for await next in inputs {
    perform(try machine.handle(next))
  }
}
