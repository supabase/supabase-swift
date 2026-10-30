//
//  ClientState.swift
//  Realtime
//

import Foundation

/// What the edges of the client hand to its actor: the socket reader, timers, connect attempts,
/// token fetches, stream terminations, task cancellations, and app lifecycle changes.
///
/// An edge holds only the inbox continuation, never the client, and one pump task feeds the
/// inputs to the actor in the order they were yielded.
enum Input: Sendable {
  /// A decoded frame, or the close, of the socket installed at `generation`.
  case socket(SocketInput, generation: Int)
  case connectEnded(Result<any WebSocketConnection, any Error>, attempt: Int)
  case timerFired(TimerID, token: UInt64)
  case retryTimerFired(token: UInt64)
  case idleTimerFired(token: UInt64)
  case tokenFetched(String?, generation: Int)
  case streamEnded(StreamID)
  case waiterCancelled(WaiterID)
  case appBackground
  case appForeground
  /// Resumes once every earlier input is applied.
  case flush(CheckedContinuation<Void, Never>)
}

/// What the socket reader decodes off the actor. A frame that fails to decode is logged by the
/// reader and never becomes an input.
enum SocketInput: Sendable {
  case frame(RealtimeMessage)
  case binaryBroadcast(DecodedBroadcast)
  case closed(code: Int?, reason: String?)
}

/// Identifies one stream the client handed out. `channel` is `nil` for client streams.
struct StreamID: Hashable, Sendable {
  let rawValue: UInt64
  let channel: ChannelID?
}

/// Fans one writer out to any number of `AsyncStream` subscribers.
///
/// Subscribing is synchronous, so a stream taken before a command sees every element the command
/// causes. A fan-out made with ``init(retaining:)`` is state-like: a new subscriber first
/// receives the current element.
///
/// The client actor owns its fan-outs, so they need no lock and are not `Sendable`. They end
/// their own streams in `deinit`: the actor's `deinit` is nonisolated, and the compiler refuses
/// access to non-`Sendable` state there, so a stream cleanup written in the actor's `deinit`
/// does not compile.
///
/// A stream's `onTermination` runs on whatever context ends the stream, so it must only hand the
/// ID back to the actor. ``finish()`` clears it first, so an end the owner causes sends nothing.
final class Fanout<Element: Sendable> {
  private struct Subscriber {
    let filter: ((Element) -> Bool)?
    let continuation: AsyncStream<Element>.Continuation
  }

  private var subscribers: [StreamID: Subscriber] = [:]
  private let retains: Bool
  private var isFinished = false

  /// The latest element of a state fan-out, or `nil` for an event fan-out.
  private(set) var current: Element?

  /// An event fan-out: subscribers see only the elements yielded after they subscribe.
  init() {
    retains = false
  }

  /// A state fan-out: subscribers first receive the latest element, or `initial` before the
  /// first yield.
  init(retaining initial: Element) {
    current = initial
    retains = true
  }

  deinit {
    finish()
  }

  /// The number of streams the fan-out feeds.
  var count: Int { subscribers.count }

  /// Returns a stream of the elements yielded from now on, preceded by the current element if
  /// the fan-out retains one.
  ///
  /// `filter` applies to yielded elements only; the current element is always replayed.
  /// `onTermination` runs when the consumer ends the stream, never when ``finish()`` does.
  func subscribe(
    _ id: StreamID,
    where filter: ((Element) -> Bool)? = nil,
    onTermination: @escaping @Sendable () -> Void
  ) -> AsyncStream<Element> {
    let (stream, continuation) = AsyncStream.makeStream(of: Element.self)
    if let current { continuation.yield(current) }
    guard !isFinished else {
      continuation.finish()
      return stream
    }
    continuation.onTermination = { _ in onTermination() }
    subscribers[id] = Subscriber(filter: filter, continuation: continuation)
    return stream
  }

  /// Delivers `element` to every matching subscriber. Ignored once finished.
  ///
  /// Drops the subscribers whose consumer already ended the stream.
  func yield(_ element: Element) {
    guard !isFinished else { return }
    if retains { current = element }
    for (id, subscriber) in subscribers where subscriber.filter?(element) ?? true {
      if case .terminated = subscriber.continuation.yield(element) {
        subscribers[id] = nil
      }
    }
  }

  /// Forgets the stream `id`, which its consumer already ended. Does not end the stream. Returns
  /// whether the fan-out had it.
  @discardableResult
  func remove(_ id: StreamID) -> Bool {
    subscribers.removeValue(forKey: id) != nil
  }

  /// Ends every stream. Later subscribers get the current element, then an immediate finish.
  func finish() {
    guard !isFinished else { return }
    isFinished = true
    let ended = subscribers
    subscribers = [:]
    for subscriber in ended.values {
      subscriber.continuation.onTermination = nil
      subscriber.continuation.finish()
    }
  }
}

/// Everything the client keeps for one channel: the handle, the fan-outs behind its streams, and
/// its open Postgres bindings.
///
/// The client actor owns it, so it needs no lock and is not `Sendable`. It ends its own streams
/// in `deinit`: the actor's `deinit` is nonisolated, and the compiler refuses access to
/// non-`Sendable` state there, so a stream cleanup written in the actor's `deinit` does not
/// compile. It holds the handle strongly, so a channel the app released stays alive for as long
/// as the client keeps its state.
final class ChannelState {
  private struct Binding {
    let id: StreamID
    let config: PostgresJoinConfig
    let continuation: AsyncStream<PostgresChange>.Continuation
  }

  let handle: RealtimeChannel
  let status = Fanout<RealtimeChannelStatus>(retaining: .unsubscribed)
  let events = Fanout<RealtimeChannelEvent>()
  let broadcasts = Fanout<BroadcastMessage>()
  let presenceChanges = Fanout<PresenceChange>()
  let presenceStates = Fanout<PresenceState>(retaining: PresenceState())

  private var postgres: [Binding] = []
  private var isSpent = false

  init(handle: RealtimeChannel) {
    self.handle = handle
  }

  deinit {
    finishAll()
  }

  /// What a join payload depends on besides the configuration. Postgres bindings keep their
  /// registration order, which fixes the `postgres_changes` array of the payload. Presence is
  /// enabled while a presence stream is open.
  var joinSnapshot: JoinSnapshot {
    JoinSnapshot(
      bindings: postgres.map(\.config),
      presenceEnabled: presenceChanges.count + presenceStates.count > 0)
  }

  /// Registers `config` and returns the changes the server matches to it. The binding stays
  /// until ``removeStream(_:)`` or ``finishAll()``.
  func addPostgresStream(
    _ id: StreamID,
    _ config: PostgresJoinConfig,
    onTermination: @escaping @Sendable () -> Void
  ) -> AsyncStream<PostgresChange> {
    let (stream, continuation) = AsyncStream.makeStream(of: PostgresChange.self)
    guard !isSpent else {
      continuation.finish()
      return stream
    }
    continuation.onTermination = { _ in onTermination() }
    postgres.append(Binding(id: id, config: config, continuation: continuation))
    return stream
  }

  /// Forgets the stream `id`, whichever kind it is, after its consumer ended it. Returns `true`
  /// only when it removed a Postgres binding, because only that changes the join payload.
  @discardableResult
  func removeStream(_ id: StreamID) -> Bool {
    if status.remove(id) || events.remove(id) || broadcasts.remove(id)
      || presenceChanges.remove(id) || presenceStates.remove(id)
    {
      return false
    }
    guard let index = postgres.firstIndex(where: { $0.id == id }) else { return false }
    postgres.remove(at: index)
    return true
  }

  /// Hands `delivery` to the streams it belongs to. A Postgres change reaches only the bindings
  /// the server matched it to.
  func deliver(_ delivery: Delivery) {
    switch delivery {
    case .broadcast(let message):
      broadcasts.yield(message)
    case .postgres(let delivery):
      for binding in postgres where delivery.matched.contains(binding.config) {
        binding.continuation.yield(delivery.change)
      }
    case .presence(let change, let state):
      presenceChanges.yield(change)
      presenceStates.yield(state)
    case .event(let event):
      events.yield(event)
    }
  }

  /// Ends every stream. Streams added afterwards end at once.
  func finishAll() {
    isSpent = true
    status.finish()
    events.finish()
    broadcasts.finish()
    presenceChanges.finish()
    presenceStates.finish()
    let ended = postgres
    postgres = []
    for binding in ended {
      binding.continuation.onTermination = nil
      binding.continuation.finish()
    }
  }
}
