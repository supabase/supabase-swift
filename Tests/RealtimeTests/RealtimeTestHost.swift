//
//  RealtimeTestHost.swift
//  RealtimeTests
//
//  Created by Guilherme Souza on 19/10/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import Helpers
import TestHelpers
import Testing

@testable import Realtime

/// A `RealtimeClient` on a `TestClock`, wired to an in-memory socket pair per connect, that
/// signals every change a test might wait for: a status change, a new socket, or a frame
/// from the client.
///
/// Tests wait with ``waitUntil(timeout:_:sourceLocation:)`` or ``receive(where:timeout:sourceLocation:)``.
/// Both return as soon as the condition holds and record an issue after a wall-clock timeout,
/// so a broken test fails fast instead of hanging, and no test yields in a loop hoping the
/// scheduler ran. One wait at a time: the signal has a single consumer.
final class RealtimeTestHost: Sendable {
  let clock = TestClock<Duration>()
  let client: RealtimeClient

  private struct State {
    var sockets: [FakeWebSocket] = []
    var servers: [FakeWebSocket] = []
    var frames: [RealtimeMessage] = []
    var statuses: [RealtimeClientStatus] = []
    var observers: [Task<Void, Never>] = []
  }

  private let state = LockIsolated(State())
  private let signal: AsyncStream<Void>
  private let signalContinuation: AsyncStream<Void>.Continuation

  init(
    url: URL = URL(string: "http://localhost:54321/realtime/v1")!,
    options: RealtimeClientOptions = RealtimeClientOptions(handleAppLifecycle: false),
    http: HTTPClient = HTTPClient(transport: RecordingTransport())
  ) async {
    // Newest-1: a wait only needs to know that something changed since it last looked.
    (signal, signalContinuation) = AsyncStream<Void>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let state = state
    let continuation = signalContinuation

    client = RealtimeClient(
      url: url,
      options: options,
      wsTransport: { _, _ in
        let (socket, server) = FakeWebSocket.fakes()
        let observer = Task {
          let serializer = RealtimeSerializer()
          for await event in server.events {
            if case .frame(.text(let text)) = event, let message = try? serializer.decodeText(text)
            {
              state.withValue { $0.frames.append(message) }
            }
            continuation.yield()
          }
        }
        state.withValue {
          $0.sockets.append(socket)
          $0.servers.append(server)
          $0.observers.append(observer)
        }
        continuation.yield()
        return socket
      },
      http: http,
      clock: clock
    )

    let statusChanges = await client.statusChanges()
    let statusObserver = Task {
      for await status in statusChanges {
        state.withValue { $0.statuses.append(status) }
        continuation.yield()
      }
    }
    state.withValue { $0.observers.append(statusObserver) }
  }

  deinit {
    signalContinuation.finish()
    for observer in state.value.observers {
      observer.cancel()
    }
  }

  // MARK: Observations

  /// The server side of the latest socket.
  var server: FakeWebSocket? { state.value.servers.last }

  /// The server side of every socket opened, in order.
  var servers: [FakeWebSocket] { state.value.servers }

  /// The client side of every socket opened, in order.
  var sockets: [FakeWebSocket] { state.value.sockets }

  /// How many times the transport was asked for a socket.
  var connectCount: Int { state.value.sockets.count }

  /// Every text frame the client sent, decoded, across all sockets.
  var frames: [RealtimeMessage] { state.value.frames }

  /// Every client status observed, starting with the one at creation.
  var statuses: [RealtimeClientStatus] { state.value.statuses }

  // MARK: Waiting

  /// Returns once `condition` holds. It is re-checked on every signal and the wait records
  /// an issue after `timeout` of wall-clock time.
  func waitUntil(
    timeout: Duration = .seconds(5),
    _ condition: @escaping @Sendable () async -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async {
    if await condition() { return }
    do {
      try await withTimeout(timeout, clock: ContinuousClock()) {
        for await _ in signal where await condition() {
          return
        }
      }
    } catch {
      Issue.record("Condition not met within \(timeout).", sourceLocation: sourceLocation)
    }
  }

  /// The first frame the client sent that matches `predicate`, waiting for it if needed.
  func receive(
    where predicate: @escaping @Sendable (RealtimeMessage) -> Bool,
    timeout: Duration = .seconds(5),
    sourceLocation: SourceLocation = #_sourceLocation
  ) async throws -> RealtimeMessage {
    await waitUntil(
      timeout: timeout, { [state] in state.value.frames.contains(where: predicate) },
      sourceLocation: sourceLocation
    )
    return try #require(frames.first(where: predicate), sourceLocation: sourceLocation)
  }

  /// The first frame with `event` the client sent, waiting for it if needed.
  func receive(
    event: String,
    timeout: Duration = .seconds(5),
    sourceLocation: SourceLocation = #_sourceLocation
  ) async throws -> RealtimeMessage {
    try await receive(
      where: { $0.event == event }, timeout: timeout, sourceLocation: sourceLocation)
  }

  // MARK: Scripting the server

  /// Answers `message` from the server with a `phx_reply`.
  func reply(to message: RealtimeMessage, status: PushStatus = .ok, response: JSONObject = [:]) {
    server?.send(
      RealtimeMessage(
        joinRef: message.joinRef,
        ref: message.ref,
        topic: message.topic,
        event: "phx_reply",
        payload: ["status": .string(status.rawValue), "response": .object(response)]
      )
    )
  }

  /// Confirms a `phx_join` the way the server does: a `phx_reply` carrying `postgres_changes`.
  func confirmJoin(_ join: RealtimeMessage, postgresChanges: [JSONValue] = []) {
    reply(to: join, response: ["postgres_changes": .array(postgresChanges)])
  }

  /// Subscribes `channel` and confirms its join. Returns the join.
  @discardableResult
  func subscribe(_ channel: RealtimeChannel) async throws -> RealtimeMessage {
    let subscription = Task { try await channel.subscribe() }
    let join = try await receive {
      $0.event == ChannelEvent.join && $0.topic == channel.wireTopic
    }
    confirmJoin(join)
    try await subscription.value
    return join
  }

  /// Closes the channel that `join` opened, as the server does with `phx_close`.
  func sendClose(for join: RealtimeMessage) {
    server?.send(
      RealtimeMessage(
        joinRef: join.joinRef, ref: nil, topic: join.topic, event: ChannelEvent.close,
        payload: [:]))
  }
}

/// Records an issue unless `action` throws a ``RealtimeError`` with the failure of `expected`.
func expectError(
  _ expected: RealtimeError,
  sourceLocation: SourceLocation = #_sourceLocation,
  _ action: () async throws -> Void
) async {
  do {
    try await action()
    Issue.record("Expected \(expected.kind)", sourceLocation: sourceLocation)
  } catch let error as RealtimeError {
    #expect(error.isSameFailure(as: expected), sourceLocation: sourceLocation)
  } catch {
    Issue.record("Unexpected \(error)", sourceLocation: sourceLocation)
  }
}

extension RealtimeClient {
  /// The id of the core record for `topic`, if there is one: the live channel's record first,
  /// then any other record of the topic, such as one still leaving.
  private func recordID(for topic: String) -> ChannelID? {
    if let id = liveChannelState(for: topic)?.handle.id, core.channels[id] != nil { return id }
    return core.channels.first { $0.value.topic == topic }?.key
  }

  /// The channel ``channel(_:configure:)`` returns for `topic`, without creating one.
  func liveChannel(for topic: String) -> RealtimeChannel? {
    liveChannelState(for: topic)?.handle
  }

  /// Ends every stream of `channel`, as removing it would, but keeps it registered. A test then
  /// reads what a stream had buffered without waiting for more.
  func finishStreams(of channel: RealtimeChannel) {
    state(of: channel)?.finishAll()
  }

  /// The Postgres bindings of the open streams of `channel`, in registration order.
  func bindings(of channel: RealtimeChannel) -> [PostgresJoinConfig] {
    state(of: channel)?.joinSnapshot.bindings ?? []
  }

  /// Whether a presence stream of `channel` is open, which enables presence on its join.
  func hasPresenceListener(_ channel: RealtimeChannel) -> Bool {
    state(of: channel)?.joinSnapshot.presenceEnabled ?? false
  }

  /// How many streams of each kind `channel` feeds.
  struct StreamCounts: Equatable {
    var events = 0
    var broadcasts = 0
    var presenceChanges = 0
    var presenceStates = 0
    var postgres = 0
  }

  func streamCounts(of channel: RealtimeChannel) -> StreamCounts {
    guard let state = state(of: channel) else { return StreamCounts() }
    return StreamCounts(
      events: state.events.count,
      broadcasts: state.broadcasts.count,
      presenceChanges: state.presenceChanges.count,
      presenceStates: state.presenceStates.count,
      postgres: state.joinSnapshot.bindings.count)
  }

  /// Gives the core a subscribed channel for `topic`, as a confirmed join would, so frames for
  /// it reach the channel's streams without a socket. The client must have a channel for `topic`.
  func installSubscribedRecord(_ topic: String, joinRef: String = "1") {
    guard let id = liveChannelState(for: topic)?.handle.id else {
      preconditionFailure("No channel for '\(topic)'")
    }
    var record = ChannelRecord(topic: topic, configuration: RealtimeChannelConfiguration())
    record.phase = .subscribed(joinRef: joinRef)
    record.hasBeenSubscribed = true
    core.channels[id] = record
  }

  /// Whether the core has a record for `topic`.
  func hasRecord(for topic: String) -> Bool {
    recordID(for: topic) != nil
  }

  /// How many pushes on the channel for `topic` wait for a reply.
  func pendingPushCount(for topic: String) -> Int {
    recordID(for: topic).flatMap { core.channels[$0]?.pendingPushes.count } ?? 0
  }

  /// The error the connection state carries.
  var connectionError: RealtimeError? { core.connection.error }

  /// The ref of the heartbeat the server has not acknowledged yet.
  var pendingHeartbeatRef: String? { core.pendingHeartbeat?.ref }

  /// The ref of the join the core can still confirm, or already confirmed, for `topic`.
  func joinRef(for topic: String) -> String? {
    recordID(for: topic).flatMap { core.channels[$0]?.currentJoinRef }
  }

  /// What the join in flight for `topic` waits for, or `nil` when no join is in flight.
  func joinStage(for topic: String) -> ChannelRecord.JoinStage? {
    guard let id = recordID(for: topic),
      case .joining(_, _, let stage)? = core.channels[id]?.phase
    else { return nil }
    return stage
  }
}

extension RealtimeChannel {
  /// The ref of the join the server can still confirm, or already confirmed.
  var joinRef: String? {
    get async { await client?.joinRef(for: topic) }
  }

  /// What the join in flight waits for, or `nil` when no join is in flight.
  var joinStage: ChannelRecord.JoinStage? {
    get async { await client?.joinStage(for: topic) }
  }
}
