//
//  RealtimeCoreConnectionTests.swift
//  RealtimeTests
//

import Foundation
import TestHelpers
import Testing

@testable import Realtime

/// The connection table, connect waiters, heartbeat, and app lifecycle of ``RealtimeCore``. No
/// actor, no clock, no socket traffic: each row is a (state, event) pair and the (state,
/// effects) it must produce.
@Suite
struct RealtimeCoreConnectionTests {
  typealias State = RealtimeClient.ConnectionState
  typealias Event = RealtimeCore.Event
  typealias Effect = RealtimeCore.Effect

  let socket = FakeWebSocket.fakes().0
  let other = FakeWebSocket.fakes().0

  static let dropped = RealtimeError.socketClosed(
    code: WebSocketCloseCode(rawValue: 1001), reason: "going away")
  static let unreachable = RealtimeError.transport("unreachable")
  static let refused = RealtimeError.upgradeFailed(status: 401)
  static let jwtExpired = RealtimeError.socketClosed(
    code: WebSocketCloseCode(rawValue: 4001), reason: "jwt expired")

  static let heartbeatEvery = Effect.schedule(.heartbeat, after: .seconds(25))

  struct Row {
    var from: State
    var event: Event
    var to: State
    var effects: [Effect]
    var line: Int

    init(from: State, _ event: Event, to: State, effects: [Effect], line: Int = #line) {
      self.from = from
      self.event = event
      self.to = to
      self.effects = effects
      self.line = line
    }
  }

  var waiting: State {
    .reconnecting(attempt: 2, retryIn: .seconds(2), lastError: Self.dropped)
  }

  var rows: [Row] {
    [
      // connect()
      Row(
        from: .disconnected(nil), .connect(waiter: nil), to: .connecting(attempt: 1),
        effects: [.publishClientStatus(.connecting(attempt: 1)), .openSocket]),
      Row(
        from: .disconnected(Self.refused), .connect(waiter: nil), to: .connecting(attempt: 1),
        effects: [.publishClientStatus(.connecting(attempt: 1)), .openSocket]),
      Row(
        from: .connecting(attempt: 1), .connect(waiter: nil), to: .connecting(attempt: 1),
        effects: []),
      Row(from: .connected(socket), .connect(waiter: nil), to: .connected(socket), effects: []),
      // An explicit connect() skips the rest of the backoff wait.
      Row(
        from: waiting, .connect(waiter: nil), to: .connecting(attempt: 3),
        effects: [.publishClientStatus(.connecting(attempt: 3)), .cancelRetry, .openSocket]),

      // The transport answered.
      Row(
        from: .connecting(attempt: 1), .socketOpened(socket), to: .connected(socket),
        effects: [
          .publishClientStatus(.connected), .installSocket(socket, rejoinChannels: false),
          Self.heartbeatEvery,
        ]),
      Row(
        from: .connecting(attempt: 3), .socketOpened(socket), to: .connected(socket),
        effects: [
          .publishClientStatus(.connected), .installSocket(socket, rejoinChannels: true),
          Self.heartbeatEvery,
        ]),
      Row(
        from: .disconnected(nil), .socketOpened(socket), to: .disconnected(nil),
        effects: [.closeSocket(socket, code: nil, reason: "Connection cancelled")]),
      Row(
        from: waiting, .socketOpened(socket), to: waiting,
        effects: [.closeSocket(socket, code: nil, reason: "Connection cancelled")]),
      Row(
        from: .connected(socket), .socketOpened(other), to: .connected(socket),
        effects: [.closeSocket(other, code: nil, reason: "Connection cancelled")]),

      // The first connect() reports its failure to the caller and stops.
      Row(
        from: .connecting(attempt: 1), .socketOpenFailed(Self.unreachable),
        to: .disconnected(Self.unreachable),
        effects: [.publishClientStatus(.disconnected(Self.unreachable))]),
      // A failed retry waits longer and tries again.
      Row(
        from: .connecting(attempt: 3), .socketOpenFailed(Self.unreachable),
        to: .reconnecting(attempt: 3, retryIn: .seconds(3), lastError: Self.unreachable),
        effects: [
          .publishClientStatus(
            .reconnecting(attempt: 3, retryIn: .seconds(3), lastError: Self.unreachable)),
          .scheduleRetry(after: .seconds(3)),
        ]),
      // A refused upgrade (401/403/404) cannot succeed by retrying.
      Row(
        from: .connecting(attempt: 3), .socketOpenFailed(Self.refused),
        to: .disconnected(Self.refused),
        effects: [.publishClientStatus(.disconnected(Self.refused))]),
      Row(from: waiting, .socketOpenFailed(Self.unreachable), to: waiting, effects: []),
      Row(
        from: .disconnected(nil), .socketOpenFailed(Self.unreachable), to: .disconnected(nil),
        effects: []),

      // The retry timer.
      Row(
        from: waiting, .retryTimerFired, to: .connecting(attempt: 3),
        effects: [.publishClientStatus(.connecting(attempt: 3)), .openSocket]),
      Row(
        from: .connecting(attempt: 3), .retryTimerFired, to: .connecting(attempt: 3), effects: []),
      Row(from: .connected(socket), .retryTimerFired, to: .connected(socket), effects: []),
      Row(from: .disconnected(nil), .retryTimerFired, to: .disconnected(nil), effects: []),

      // A wake (foreground, network back) only matters while waiting to retry.
      Row(
        from: waiting, .wake, to: .connecting(attempt: 3),
        effects: [.publishClientStatus(.connecting(attempt: 3)), .cancelRetry, .openSocket]),
      Row(from: .connecting(attempt: 1), .wake, to: .connecting(attempt: 1), effects: []),
      Row(from: .connected(socket), .wake, to: .connected(socket), effects: []),
      Row(from: .disconnected(nil), .wake, to: .disconnected(nil), effects: []),

      // disconnect()
      Row(
        from: .connected(socket), .disconnectRequested(code: 1000, reason: "bye"),
        to: .disconnected(nil),
        effects: [
          .publishClientStatus(.disconnected(nil)), .cancelAllTasks,
          .closeSocket(socket, code: 1000, reason: "bye"), .cancel(.heartbeat),
        ]),
      Row(
        from: .connected(socket), .disconnectRequested(code: nil, reason: nil),
        to: .disconnected(nil),
        effects: [
          .publishClientStatus(.disconnected(nil)), .cancelAllTasks,
          .closeSocket(socket, code: nil, reason: "Client disconnect"), .cancel(.heartbeat),
        ]),
      Row(
        from: .connecting(attempt: 1), .disconnectRequested(code: nil, reason: nil),
        to: .disconnected(nil),
        effects: [.publishClientStatus(.disconnected(nil)), .cancelAllTasks]),
      Row(
        from: waiting, .disconnectRequested(code: nil, reason: nil), to: .disconnected(nil),
        effects: [.publishClientStatus(.disconnected(nil)), .cancelAllTasks]),
      Row(
        from: .disconnected(Self.refused), .disconnectRequested(code: nil, reason: nil),
        to: .disconnected(nil),
        effects: [.publishClientStatus(.disconnected(nil)), .cancelAllTasks]),
      Row(
        from: .disconnected(nil), .disconnectRequested(code: nil, reason: nil),
        to: .disconnected(nil), effects: [.cancelAllTasks]),

      // The socket went away.
      Row(
        from: .connected(socket), .socketClosed(code: 1001, reason: "going away"),
        to: .reconnecting(attempt: 1, retryIn: .seconds(1), lastError: Self.dropped),
        effects: [
          .publishClientStatus(
            .reconnecting(attempt: 1, retryIn: .seconds(1), lastError: Self.dropped)),
          .stopSocketLoops, .scheduleRetry(after: .seconds(1)), .cancel(.heartbeat),
        ]),
      Row(
        from: .connected(socket), .socketClosed(code: nil, reason: nil),
        to: .reconnecting(
          attempt: 1, retryIn: .seconds(1),
          lastError: .socketClosed(code: nil, reason: nil)),
        effects: [
          .publishClientStatus(
            .reconnecting(
              attempt: 1, retryIn: .seconds(1), lastError: .socketClosed(code: nil, reason: nil))
          ),
          .stopSocketLoops, .scheduleRetry(after: .seconds(1)), .cancel(.heartbeat),
        ]),
      // Application close codes (4000–4999) signal auth or protocol errors.
      Row(
        from: .connected(socket), .socketClosed(code: 4001, reason: "jwt expired"),
        to: .disconnected(Self.jwtExpired),
        effects: [
          .publishClientStatus(.disconnected(Self.jwtExpired)), .stopSocketLoops,
          .cancel(.heartbeat),
        ]),
      Row(
        from: .connected(socket), .socketFailed(.heartbeatTimeout),
        to: .reconnecting(attempt: 1, retryIn: .seconds(1), lastError: .heartbeatTimeout),
        effects: [
          .publishClientStatus(
            .reconnecting(attempt: 1, retryIn: .seconds(1), lastError: .heartbeatTimeout)),
          .closeSocket(socket, code: 1001, reason: "error: heartbeat timeout"),
          .stopSocketLoops,
          .scheduleRetry(after: .seconds(1)),
          .cancel(.heartbeat),
        ]),
      Row(
        from: .connecting(attempt: 1), .socketClosed(code: 1001, reason: nil),
        to: .connecting(attempt: 1), effects: []),
      Row(from: waiting, .socketClosed(code: 1001, reason: nil), to: waiting, effects: []),
      Row(
        from: .disconnected(nil), .socketClosed(code: 1001, reason: nil), to: .disconnected(nil),
        effects: []),
      Row(
        from: .connecting(attempt: 1), .socketFailed(.heartbeatTimeout),
        to: .connecting(attempt: 1), effects: []),
      Row(from: waiting, .socketFailed(.heartbeatTimeout), to: waiting, effects: []),
      Row(
        from: .disconnected(nil), .socketFailed(.heartbeatTimeout), to: .disconnected(nil),
        effects: []),

      // Channels come and go. The first subscribe cancels the idle disconnect (channel tests).
      Row(
        from: .connected(socket), .lastChannelRemoved(disconnectAfter: .seconds(50)),
        to: .connected(socket), effects: [.scheduleIdleDisconnect(after: .seconds(50))]),
      Row(
        from: .connecting(attempt: 1), .lastChannelRemoved(disconnectAfter: .seconds(50)),
        to: .connecting(attempt: 1), effects: [.scheduleIdleDisconnect(after: .seconds(50))]),
      Row(
        from: waiting, .lastChannelRemoved(disconnectAfter: .seconds(50)), to: waiting,
        effects: [.scheduleIdleDisconnect(after: .seconds(50))]),
      Row(
        from: .disconnected(nil), .lastChannelRemoved(disconnectAfter: .seconds(50)),
        to: .disconnected(nil), effects: []),
    ]
  }

  @Test
  func table() {
    for row in rows {
      var harness = CoreHarness()
      harness.core.connection = row.from
      let effects = harness.send(row.event)
      let location = SourceLocation(
        fileID: #fileID, filePath: #filePath, line: row.line, column: 1)
      #expect(
        harness.core.connection == row.to, "state after \(row.event)", sourceLocation: location)
      #expect(effects == row.effects, "effects after \(row.event)", sourceLocation: location)
    }
  }

  // MARK: Connect waiters

  @Test
  func connectWaiterResolvesOnSocketOpened() {
    var harness = CoreHarness()
    let waiter = harness.waiter()

    #expect(
      harness.send(.connect(waiter: waiter))
        == [.publishClientStatus(.connecting(attempt: 1)), .openSocket])

    let effects = harness.send(.socketOpened(socket))
    #expect(effects.contains(.resume(waiter, .success)))
    #expect(effects.contains(.publishClientStatus(.connected)))
  }

  @Test
  func connectWaiterFailsWhenFirstAttemptFails() {
    var harness = CoreHarness()
    let waiter = harness.waiter()
    _ = harness.send(.connect(waiter: waiter))

    let effects = harness.send(.socketOpenFailed(Self.unreachable))

    #expect(effects.contains(.resume(waiter, .failure(Self.unreachable))))
  }

  @Test
  func connectWhileConnectedResolvesAtOnce() {
    var harness = CoreHarness.connected()
    let waiter = harness.waiter()

    #expect(harness.send(.connect(waiter: waiter)) == [.resume(waiter, .success)])
  }

  @Test
  func connectWhileConnectingWaitsForTheSameAttempt() {
    var harness = CoreHarness()
    let first = harness.waiter()
    let second = harness.waiter()
    _ = harness.send(.connect(waiter: first))

    #expect(harness.send(.connect(waiter: second)) == [])
    #expect(
      harness.send(.socketOpened(socket)) == [
        .publishClientStatus(.connected), .installSocket(socket, rejoinChannels: false),
        Self.heartbeatEvery, .resume(first, .success), .resume(second, .success),
      ])
  }

  /// A connect() during the backoff tries at once. When that attempt fails, the caller gets the
  /// error and the automatic reconnect carries on.
  @Test
  func connectDuringBackoffFailsWhenItsAttemptFails() {
    var harness = CoreHarness()
    harness.core.connection = waiting
    let waiter = harness.waiter()
    _ = harness.send(.connect(waiter: waiter))

    #expect(
      harness.send(.socketOpenFailed(Self.unreachable)) == [
        .publishClientStatus(
          .reconnecting(attempt: 3, retryIn: .seconds(3), lastError: Self.unreachable)),
        .scheduleRetry(after: .seconds(3)),
        .resume(waiter, .failure(Self.unreachable)),
      ])
  }

  @Test
  func disconnectCancelsConnectWaiters() {
    var harness = CoreHarness()
    let waiter = harness.waiter()
    _ = harness.send(.connect(waiter: waiter))

    #expect(
      harness.send(.disconnectRequested(code: nil, reason: nil)) == [
        .publishClientStatus(.disconnected(nil)), .cancelAllTasks, .resume(waiter, .cancelled),
      ])
  }

  // MARK: Heartbeat

  @Test
  func heartbeatTimerSendsHeartbeatThenTimesOut() throws {
    var harness = CoreHarness.connected()
    let socket = try #require(harness.socket)

    #expect(
      harness.send(.timerFired(.heartbeat)) == [
        .send(Self.heartbeat(ref: "1")), .publishHeartbeat(.sent), Self.heartbeatEvery,
      ])

    harness.advance(by: .seconds(25))
    var failed = harness
    let failure = failed.send(.socketFailed(.heartbeatTimeout))
    #expect(failure.contains(.closeSocket(socket, code: 1001, reason: "error: heartbeat timeout")))

    #expect(harness.send(.timerFired(.heartbeat)) == [.publishHeartbeat(.timedOut)] + failure)
    #expect(harness.core.connection == failed.core.connection)
  }

  @Test
  func heartbeatReplyPublishesLatency() {
    var harness = CoreHarness.connected()
    _ = harness.send(.timerFired(.heartbeat))
    harness.advance(by: .seconds(2))

    #expect(
      harness.send(.frame(Self.heartbeatReply(ref: "1")))
        == [.publishHeartbeat(.acknowledged(latency: .seconds(2)))])
    // Acknowledged: the next tick sends a new heartbeat instead of timing out.
    #expect(
      harness.send(.timerFired(.heartbeat)) == [
        .send(Self.heartbeat(ref: "2")), .publishHeartbeat(.sent), Self.heartbeatEvery,
      ])
  }

  /// Any reply proves the socket is alive, which is all a heartbeat checks.
  @Test
  func heartbeatErrorReplyStillAcknowledges() {
    var harness = CoreHarness.connected()
    _ = harness.send(.timerFired(.heartbeat))

    #expect(
      harness.send(.frame(Self.heartbeatReply(ref: "1", status: "error")))
        == [.publishHeartbeat(.acknowledged(latency: .zero))])
  }

  @Test
  func replyToAnotherRefIsNotAHeartbeatAcknowledgement() {
    var harness = CoreHarness.connected()
    _ = harness.send(.timerFired(.heartbeat))

    #expect(harness.send(.frame(Self.heartbeatReply(ref: "9"))) == [])
    #expect(harness.send(.timerFired(.heartbeat)).first == .publishHeartbeat(.timedOut))
  }

  @Test
  func heartbeatTimerIsIgnoredWhileNotConnected() {
    var harness = CoreHarness()
    #expect(harness.send(.timerFired(.heartbeat)) == [])

    harness.core.connection = waiting
    #expect(harness.send(.timerFired(.heartbeat)) == [])
  }

  /// A heartbeat that was pending on the old socket can never be acknowledged on the new one;
  /// it must not count as a timeout there.
  @Test
  func reconnectForgetsThePendingHeartbeat() {
    var harness = CoreHarness.connected()
    _ = harness.send(.timerFired(.heartbeat))
    _ = harness.send(.socketClosed(code: 1001, reason: "going away"))
    _ = harness.send(.retryTimerFired)
    _ = harness.send(.socketOpened(other))

    #expect(
      harness.send(.timerFired(.heartbeat)) == [
        .send(Self.heartbeat(ref: "2")), .publishHeartbeat(.sent), Self.heartbeatEvery,
      ])
  }

  @Test
  func disconnectRestartsRefs() {
    var harness = CoreHarness.connected()
    _ = harness.send(.timerFired(.heartbeat))
    _ = harness.send(.disconnectRequested(code: nil, reason: nil))
    _ = harness.send(.connect(waiter: nil))
    _ = harness.send(.socketOpened(other))

    #expect(harness.send(.timerFired(.heartbeat)).first == .send(Self.heartbeat(ref: "1")))
  }

  // MARK: App lifecycle

  @Test
  func foregroundAfterDropWhileBackgroundedSkipsTheBackoff() {
    var harness = CoreHarness.connected()
    #expect(harness.send(.appBackground) == [])
    _ = harness.send(.socketClosed(code: 1001, reason: "going away"))

    #expect(
      harness.send(.appForeground) == [
        .publishClientStatus(.connecting(attempt: 2)), .cancelRetry, .openSocket,
      ])
  }

  @Test
  func foregroundAfterFatalCloseWhileBackgroundedConnectsAgain() {
    var harness = CoreHarness.connected()
    _ = harness.send(.appBackground)
    _ = harness.send(.socketClosed(code: 4001, reason: "jwt expired"))

    #expect(
      harness.send(.appForeground) == [
        .publishClientStatus(.connecting(attempt: 1)), .openSocket,
      ])
  }

  @Test
  func foregroundWhileStillConnectedDoesNothing() {
    var harness = CoreHarness.connected()
    _ = harness.send(.appBackground)

    #expect(harness.send(.appForeground) == [])
    // The background mark is spent: a later foreground does not reconnect.
    _ = harness.send(.socketClosed(code: 4001, reason: "jwt expired"))
    #expect(harness.send(.appForeground) == [])
  }

  @Test
  func foregroundAfterBackgroundingWhileDisconnectedDoesNothing() {
    var harness = CoreHarness()
    _ = harness.send(.appBackground)

    #expect(harness.send(.appForeground) == [])
  }

  /// A disconnect the developer asked for is not undone when the app comes back.
  @Test
  func foregroundAfterDisconnectDoesNothing() {
    var harness = CoreHarness.connected()
    _ = harness.send(.appBackground)
    _ = harness.send(.disconnectRequested(code: nil, reason: nil))

    #expect(harness.send(.appForeground) == [])
  }

  // MARK: Helpers

  static func heartbeat(ref: Ref) -> RealtimeMessage {
    RealtimeMessage(joinRef: nil, ref: ref, topic: "phoenix", event: "heartbeat", payload: [:])
  }

  static func heartbeatReply(ref: Ref, status: String = "ok") -> RealtimeMessage {
    RealtimeMessage(
      joinRef: nil, ref: ref, topic: "phoenix", event: "phx_reply",
      payload: ["status": .string(status), "response": [:]])
  }
}
