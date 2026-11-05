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
        effects: [.publishClientStatus(.connecting(attempt: 3)), .cancel(.reconnect), .openSocket]),

      // The transport answered.
      Row(
        from: .connecting(attempt: 1), .socketOpened(socket), to: .connected(socket),
        effects: [
          .publishClientStatus(.connected), .installSocket(socket),
          Self.heartbeatEvery,
        ]),
      Row(
        from: .connecting(attempt: 3), .socketOpened(socket), to: .connected(socket),
        effects: [
          .publishClientStatus(.connected), .installSocket(socket),
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
          .schedule(.reconnect, after: .seconds(3)),
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
        from: waiting, .timerFired(.reconnect), to: .connecting(attempt: 3),
        effects: [.publishClientStatus(.connecting(attempt: 3)), .openSocket]),
      Row(
        from: .connecting(attempt: 3), .timerFired(.reconnect), to: .connecting(attempt: 3),
        effects: []),
      Row(from: .connected(socket), .timerFired(.reconnect), to: .connected(socket), effects: []),
      Row(from: .disconnected(nil), .timerFired(.reconnect), to: .disconnected(nil), effects: []),

      // A wake (foreground, network back) only matters while waiting to retry.
      Row(
        from: waiting, .wake, to: .connecting(attempt: 3),
        effects: [.publishClientStatus(.connecting(attempt: 3)), .cancel(.reconnect), .openSocket]),
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
          .stopSocketLoops, .schedule(.reconnect, after: .seconds(1)), .cancel(.heartbeat),
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
          .stopSocketLoops, .schedule(.reconnect, after: .seconds(1)), .cancel(.heartbeat),
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
          .schedule(.reconnect, after: .seconds(1)),
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
        to: .connected(socket), effects: [.schedule(.idleDisconnect, after: .seconds(50))]),
      Row(
        from: .connecting(attempt: 1), .lastChannelRemoved(disconnectAfter: .seconds(50)),
        to: .connecting(attempt: 1), effects: [.schedule(.idleDisconnect, after: .seconds(50))]),
      Row(
        from: waiting, .lastChannelRemoved(disconnectAfter: .seconds(50)), to: waiting,
        effects: [.schedule(.idleDisconnect, after: .seconds(50))]),
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
        .publishClientStatus(.connected), .installSocket(socket),
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
        .schedule(.reconnect, after: .seconds(3)),
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
    _ = harness.send(.timerFired(.reconnect))
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
        .publishClientStatus(.connecting(attempt: 2)), .cancel(.reconnect), .openSocket,
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
  func foregroundWhileStillConnectedDoesNotReconnect() {
    var harness = CoreHarness.connected()
    _ = harness.send(.appBackground)
    _ = harness.send(.appForeground)

    #expect(harness.core.connection.status.isConnected)
    // The background mark is spent: a later foreground does not reconnect.
    _ = harness.send(.socketClosed(code: 4001, reason: "jwt expired"))
    #expect(harness.send(.appForeground) == [])
  }

  // MARK: Liveness probe

  static let probeDeadline = Effect.schedule(.livenessProbe, after: .seconds(5))

  /// The socket may be dead after a suspension while the status still says connected: the
  /// foreground sends a heartbeat now instead of waiting for the next tick.
  @Test
  func foregroundWhileConnectedSendsAProbeHeartbeat() {
    var harness = CoreHarness.connected()

    #expect(
      harness.send(.appForeground) == [
        .send(Self.heartbeat(ref: "1")), .publishHeartbeat(.sent), Self.heartbeatEvery,
        Self.probeDeadline,
      ])
  }

  /// A probe needs no earlier background: the platform may not report one, as on macOS wake.
  @Test
  func foregroundProbesWithoutAPriorBackground() {
    var harness = CoreHarness.connected()

    #expect(harness.send(.appForeground).contains(Self.probeDeadline))
  }

  @Test
  func probeReplyEndsTheProbe() {
    var harness = CoreHarness.connected()
    _ = harness.send(.appForeground)
    harness.advance(by: .seconds(1))

    #expect(
      harness.send(.frame(Self.heartbeatReply(ref: "1"))) == [
        .publishHeartbeat(.acknowledged(latency: .seconds(1))), .cancel(.livenessProbe),
      ])
    // A stale probe timer finds nothing to fail.
    #expect(harness.send(.timerFired(.livenessProbe)) == [])
    #expect(harness.core.connection.status.isConnected)
  }

  /// No reply within the deadline is a heartbeat timeout, and the reconnect skips the backoff.
  @Test
  func probeWithoutReplyFailsTheSocketAndReconnectsAtOnce() throws {
    var harness = CoreHarness.connected()
    let socket = try #require(harness.socket)
    _ = harness.send(.appForeground)
    harness.advance(by: .seconds(5))

    var expected = harness
    let failure = expected.send(.socketFailed(.heartbeatTimeout))
    let wake = expected.send(.wake)
    #expect(failure.contains(.closeSocket(socket, code: 1001, reason: "error: heartbeat timeout")))
    #expect(wake.contains(.openSocket))

    #expect(
      harness.send(.timerFired(.livenessProbe)) == [.publishHeartbeat(.timedOut)] + failure + wake)
    #expect(harness.core.connection == .connecting(attempt: 2))
  }

  /// A heartbeat already waits for its reply: the probe waits on it and sends no second one.
  @Test
  func foregroundWaitsOnAHeartbeatThatIsAlreadyPending() {
    var harness = CoreHarness.connected()
    _ = harness.send(.timerFired(.heartbeat))

    #expect(harness.send(.appForeground) == [Self.probeDeadline])
    #expect(
      harness.send(.frame(Self.heartbeatReply(ref: "1"))) == [
        .publishHeartbeat(.acknowledged(latency: .zero)), .cancel(.livenessProbe),
      ])
  }

  @Test
  func probeTimerIsIgnoredWithoutAProbe() {
    var harness = CoreHarness.connected()
    #expect(harness.send(.timerFired(.livenessProbe)) == [])

    // A heartbeat in flight is the heartbeat timer's to fail, not the probe's.
    _ = harness.send(.timerFired(.heartbeat))
    #expect(harness.send(.timerFired(.livenessProbe)) == [])
    #expect(harness.core.connection.status.isConnected)
  }

  @Test
  func leavingConnectedCancelsTheProbe() {
    var harness = CoreHarness.connected()
    _ = harness.send(.appForeground)

    #expect(
      harness.send(.socketClosed(code: 1001, reason: "going away")).contains(
        .cancel(.livenessProbe)))
    // The reconnect starts clean: its first heartbeat tick sends, it does not time out.
    _ = harness.send(.timerFired(.reconnect))
    _ = harness.send(.socketOpened(other))
    #expect(harness.send(.timerFired(.livenessProbe)) == [])
  }

  @Test
  func disconnectCancelsTheProbe() {
    var harness = CoreHarness.connected()
    _ = harness.send(.appForeground)

    #expect(
      harness.send(.disconnectRequested(code: nil, reason: nil)).contains(.cancel(.livenessProbe)))
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

  // MARK: Wake cooldown

  /// A harness that connected at time zero and lost the socket at `lostAt`, with a 30 s backoff,
  /// so a wake is the only thing that ends the wait early.
  static func waitingToRetry(lostAt: Duration) -> CoreHarness {
    var options = RealtimeCore.Options.test
    options.retryDelay = { _ in .seconds(30) }
    var harness = CoreHarness.connected(options: options)
    harness.advance(by: lostAt)
    _ = harness.send(.socketClosed(code: nil, reason: nil))
    return harness
  }

  /// A path that flaps in bad reception reports "back" again and again. A wake that comes less
  /// than the cooldown after the last attempt started waits for the cooldown to end.
  @Test
  func wakeInsideTheCooldownRetriesWhenItEnds() {
    var harness = Self.waitingToRetry(lostAt: .seconds(1))
    harness.advance(by: .milliseconds(500))

    #expect(harness.send(.wake) == [.schedule(.reconnect, after: .milliseconds(500))])
    #expect(
      harness.core.connection
        == .reconnecting(
          attempt: 1, retryIn: .seconds(30), lastError: .socketClosed(code: nil, reason: nil)))

    harness.advance(by: .milliseconds(500))
    #expect(harness.send(.timerFired(.reconnect)).contains(.openSocket))
    #expect(harness.core.connection == .connecting(attempt: 2))
  }

  @Test
  func wakeAfterTheCooldownRetriesAtOnce() {
    var harness = Self.waitingToRetry(lostAt: .seconds(3))

    let effects = harness.send(.wake)

    #expect(effects.contains(.cancel(.reconnect)))
    #expect(effects.contains(.openSocket))
    #expect(harness.core.connection == .connecting(attempt: 2))
  }

  /// The wake never lengthens a wait: when the backoff ends before the cooldown does, the
  /// backoff timer stays as it is.
  @Test
  func wakeInsideTheCooldownNeverDelaysTheBackoff() {
    var harness = CoreHarness.connected()
    _ = harness.send(.socketClosed(code: nil, reason: nil))
    harness.advance(by: .milliseconds(200))

    #expect(harness.send(.wake) == [])

    harness.advance(by: .milliseconds(800))
    #expect(harness.send(.timerFired(.reconnect)).contains(.openSocket))
  }

  /// Hints that pile up inside one cooldown schedule one retry, and a retry that fails quickly
  /// is followed by the next at least a cooldown after it started.
  @Test
  func flappingHintsStartOneAttemptPerCooldown() {
    var harness = Self.waitingToRetry(lostAt: .seconds(1))
    harness.advance(by: .milliseconds(200))
    #expect(harness.send(.wake) == [.schedule(.reconnect, after: .milliseconds(800))])
    harness.advance(by: .milliseconds(200))
    #expect(harness.send(.wake) == [])
    #expect(harness.send(.wake) == [])

    // The retry starts at 2 s and fails at once.
    harness.advance(by: .milliseconds(600))
    #expect(harness.send(.timerFired(.reconnect)).contains(.openSocket))
    harness.advance(by: .milliseconds(100))
    _ = harness.send(.socketOpenFailed(Self.unreachable))

    // 2.1 s: the next attempt may not start before 4 s.
    harness.advance(by: .milliseconds(400))
    #expect(harness.send(.wake) == [.schedule(.reconnect, after: .milliseconds(1500))])
  }

  /// Returning to the foreground is not a flapping path: it retries at once, whatever the
  /// last attempt's age.
  @Test
  func foregroundWhileWaitingRetriesInsideTheCooldown() {
    var harness = CoreHarness.connected()
    _ = harness.send(.appBackground)
    harness.advance(by: .milliseconds(500))
    _ = harness.send(.socketClosed(code: nil, reason: nil))
    harness.advance(by: .milliseconds(100))

    #expect(harness.send(.appForeground).contains(.openSocket))
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
