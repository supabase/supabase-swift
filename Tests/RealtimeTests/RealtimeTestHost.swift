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

#if !os(Linux)
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
      var frames: [RealtimeMessageV2] = []
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
              if case .text(let text) = event, let message = try? serializer.decodeText(text) {
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
    var frames: [RealtimeMessageV2] { state.value.frames }

    /// Every client status observed, starting with the one at creation.
    var statuses: [RealtimeClientStatus] { state.value.statuses }

    // MARK: Waiting

    /// Returns once `condition` holds. It is re-checked on every signal and the wait records
    /// an issue after `timeout` of wall-clock time.
    func waitUntil(
      timeout: Duration = .seconds(5),
      _ condition: @escaping @Sendable () -> Bool,
      sourceLocation: SourceLocation = #_sourceLocation
    ) async {
      if condition() { return }
      do {
        try await withTimeout(timeout, clock: ContinuousClock()) {
          for await _ in signal where condition() {
            return
          }
        }
      } catch {
        Issue.record("Condition not met within \(timeout).", sourceLocation: sourceLocation)
      }
    }

    /// The first frame the client sent that matches `predicate`, waiting for it if needed.
    func receive(
      where predicate: @escaping @Sendable (RealtimeMessageV2) -> Bool,
      timeout: Duration = .seconds(5),
      sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> RealtimeMessageV2 {
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
    ) async throws -> RealtimeMessageV2 {
      try await receive(
        where: { $0.event == event }, timeout: timeout, sourceLocation: sourceLocation)
    }

    // MARK: Scripting the server

    /// Answers `message` from the server with a `phx_reply`.
    func reply(to message: RealtimeMessageV2, status: PushStatus = .ok, response: JSONObject = [:])
    {
      server?.send(
        RealtimeMessageV2(
          joinRef: message.joinRef,
          ref: message.ref,
          topic: message.topic,
          event: "phx_reply",
          payload: ["status": .string(status.rawValue), "response": .object(response)]
        )
      )
    }

    /// Confirms a `phx_join` the way the server does: a `phx_reply` carrying `postgres_changes`.
    func confirmJoin(_ join: RealtimeMessageV2, postgresChanges: [JSONValue] = []) {
      reply(to: join, response: ["postgres_changes": .array(postgresChanges)])
    }
  }
#endif
