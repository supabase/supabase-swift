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
  /// The current status first, then every change.
  ///
  /// A stream made after the channel was removed yields ``RealtimeChannelStatus/unsubscribed``
  /// and ends.
  public var statusChange: AsyncStream<RealtimeChannelStatus> {
    let (stream, continuation) = AsyncStream<RealtimeChannelStatus>.makeStream(
      bufferingPolicy: .bufferingNewest(16))
    let isRemoved = state.withValue { state in
      state.publishStatus()
      continuation.yield(state.publishedStatus)
      if case .removed = state.phase { return true }
      register(.status, .status(continuation), in: &state, terminating: continuation)
      return false
    }
    if isRemoved {
      continuation.finish()
    }
    return stream
  }

  /// Returns a stream of the broadcast messages for `event`, as the server sends them: an object
  /// with `event`, `payload`, and `type` keys. Pass `"*"` to get every event.
  public func broadcastStream(event: String) -> AsyncStream<JSONObject> {
    makeStream(.broadcast(event: event)) {
      if case .broadcast(let message) = $0 { message } else { nil }
    }
  }

  /// Returns a stream of the binary payloads broadcast for `event`, as sent with
  /// ``broadcast(event:data:)``. Pass `"*"` to get every event.
  public func broadcastDataStream(event: String) -> AsyncStream<Data> {
    makeStream(.broadcastData(event: event)) {
      if case .broadcastData(let data) = $0 { data } else { nil }
    }
  }

  /// Returns a stream of the clients that join and leave the channel.
  ///
  /// An open presence stream turns presence on for the join, so make it before
  /// ``subscribeWithError()``.
  public func presenceChange() -> AsyncStream<any PresenceAction> {
    makeStream(.presence) {
      if case .presence(let action) = $0 { action } else { nil }
    }
  }

  /// Returns a stream of the `system` messages the server sends about the channel.
  public func system() -> AsyncStream<RealtimeMessageV2> {
    makeStream(.system) {
      if case .system(let message) = $0 { message } else { nil }
    }
  }

  /// Returns a stream of the rows inserted into a table.
  ///
  /// Make it before ``subscribeWithError()``, because it shapes the join request.
  ///
  /// - Parameters:
  ///   - type: Pass `InsertAction.self`.
  ///   - schema: The database schema. Defaults to `"public"`.
  ///   - table: The table name, or `nil` for every table of `schema`.
  ///   - filter: Narrows the rows. Pass `.raw("column=op.value")` for a filter string.
  ///   - select: Restricts the change payload to these columns. Needs `schema` and `table`.
  public func postgresChange(
    _ type: InsertAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: RealtimePostgresFilter? = nil,
    select: [String]? = nil
  ) -> AsyncStream<InsertAction> {
    postgresChange(.insert, schema: schema, table: table, filter: filter, select: select) {
      if case .insert(let action) = $0 { action } else { nil }
    }
  }

  /// Returns a stream of the rows updated in a table.
  ///
  /// Make it before ``subscribeWithError()``, because it shapes the join request.
  ///
  /// - Parameters:
  ///   - type: Pass `UpdateAction.self`.
  ///   - schema: The database schema. Defaults to `"public"`.
  ///   - table: The table name, or `nil` for every table of `schema`.
  ///   - filter: Narrows the rows. Pass `.raw("column=op.value")` for a filter string.
  ///   - select: Restricts the change payload to these columns. Needs `schema` and `table`.
  public func postgresChange(
    _ type: UpdateAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: RealtimePostgresFilter? = nil,
    select: [String]? = nil
  ) -> AsyncStream<UpdateAction> {
    postgresChange(.update, schema: schema, table: table, filter: filter, select: select) {
      if case .update(let action) = $0 { action } else { nil }
    }
  }

  /// Returns a stream of the rows deleted from a table.
  ///
  /// Make it before ``subscribeWithError()``, because it shapes the join request.
  ///
  /// - Parameters:
  ///   - type: Pass `DeleteAction.self`.
  ///   - schema: The database schema. Defaults to `"public"`.
  ///   - table: The table name, or `nil` for every table of `schema`.
  ///   - filter: Narrows the rows. Pass `.raw("column=op.value")` for a filter string.
  ///   - select: Restricts the change payload to these columns. Needs `schema` and `table`.
  public func postgresChange(
    _ type: DeleteAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: RealtimePostgresFilter? = nil,
    select: [String]? = nil
  ) -> AsyncStream<DeleteAction> {
    postgresChange(.delete, schema: schema, table: table, filter: filter, select: select) {
      if case .delete(let action) = $0 { action } else { nil }
    }
  }

  /// Returns a stream of every insert, update, and delete in a table.
  ///
  /// Make it before ``subscribeWithError()``, because it shapes the join request.
  ///
  /// - Parameters:
  ///   - type: Pass `AnyAction.self`.
  ///   - schema: The database schema. Defaults to `"public"`.
  ///   - table: The table name, or `nil` for every table of `schema`.
  ///   - filter: Narrows the rows. Pass `.raw("column=op.value")` for a filter string.
  ///   - select: Restricts the change payload to these columns. Needs `schema` and `table`.
  public func postgresChange(
    _ type: AnyAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: RealtimePostgresFilter? = nil,
    select: [String]? = nil
  ) -> AsyncStream<AnyAction> {
    postgresChange(.all, schema: schema, table: table, filter: filter, select: select) { $0 }
  }

  private func postgresChange<Action: Sendable>(
    _ event: PostgresChangeEvent,
    schema: String,
    table: String?,
    filter: RealtimePostgresFilter?,
    select: [String]?,
    pick: @escaping @Sendable (AnyAction) -> Action?
  ) -> AsyncStream<Action> {
    let change = PostgresJoinConfig(
      event: event, schema: schema, table: table, filter: filter?.value, select: select)
    return makeStream(.postgres(change)) {
      if case .postgres(let action) = $0 { pick(action) } else { nil }
    }
  }

  private func makeStream<Element: Sendable>(
    _ binding: ChannelBinding,
    pick: @escaping @Sendable (ChannelDelivery) -> Element?
  ) -> AsyncStream<Element> {
    let (stream, continuation) = AsyncStream<Element>.makeStream()
    let isRegistered = state.withValue { state in
      switch state.phase {
      case .removed:
        return false
      case .attached(let attachment) where attachment.leaving == nil && binding.shapesJoin:
        reportIssue(
          """
          Cannot open a \(binding.feature) stream for "\(topic)" after `subscribeWithError()`.
          Make every postgresChange and presenceChange stream before subscribing.
          """
        )
        return false
      default:
        let sink = Sink.delivery(
          yield: { delivery in
            if let element = pick(delivery) { continuation.yield(element) }
          },
          finish: { continuation.finish() }
        )
        register(binding, sink, in: &state, terminating: continuation)
        return true
      }
    }
    if !isRegistered {
      continuation.finish()
    }
    return stream
  }

  /// `onTermination` hops to a task, because it can run while a caller holds the lock.
  private func register<Element>(
    _ binding: ChannelBinding,
    _ sink: Sink,
    in state: inout State,
    terminating continuation: AsyncStream<Element>.Continuation
  ) {
    let id = state.streams.add(binding, sink)
    continuation.onTermination = { [weak self] _ in
      Task { self?.state.withValue { $0.streams.remove(id) } }
    }
  }
}

struct StreamRegistry: Sendable {
  private(set) var bindings: [ChannelBinding] = []
  private var sinks: [Sink] = []
  private var ids: [UInt64] = []
  private var nextID: UInt64 = 0

  mutating func add(_ binding: ChannelBinding, _ sink: Sink) -> UInt64 {
    let id = nextID
    nextID += 1
    bindings.append(binding)
    sinks.append(sink)
    ids.append(id)
    return id
  }

  mutating func remove(_ id: UInt64) {
    guard let index = ids.firstIndex(of: id) else { return }
    bindings.remove(at: index)
    sinks.remove(at: index)
    ids.remove(at: index)
  }

  func deliver(_ route: ChannelRoute) {
    for (binding, sink) in zip(bindings, sinks) where route.accepts(binding) {
      sink.yield(route.delivery)
    }
  }

  func yieldStatus(_ status: RealtimeChannelStatus) {
    for case .status(let continuation) in sinks {
      continuation.yield(status)
    }
  }

  var postgresChanges: [PostgresJoinConfig] {
    bindings.compactMap { if case .postgres(let change) = $0 { change } else { nil } }
  }

  /// The caller finishes the sinks outside the lock, because `finish` runs `onTermination` at
  /// once.
  mutating func removeAll() -> [Sink] {
    let removed = sinks
    bindings = []
    sinks = []
    ids = []
    return removed
  }
}

enum Sink: Sendable {
  case delivery(yield: @Sendable (ChannelDelivery) -> Void, finish: @Sendable () -> Void)
  case status(AsyncStream<RealtimeChannelStatus>.Continuation)

  func yield(_ delivery: ChannelDelivery) {
    if case .delivery(let yield, _) = self { yield(delivery) }
  }

  func finish() {
    switch self {
    case .delivery(_, let finish): finish()
    case .status(let continuation): continuation.finish()
    }
  }
}

extension ChannelBinding {
  fileprivate var shapesJoin: Bool {
    switch self {
    case .postgres, .presence: true
    default: false
    }
  }

  fileprivate var feature: String {
    if case .presence = self { "presenceChange" } else { "postgresChange" }
  }
}
