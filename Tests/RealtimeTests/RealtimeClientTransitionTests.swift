import TestHelpers
import Testing

@testable import Realtime

/// Table tests for the pure connection transition. No actor, no clock, no socket traffic: each
/// row is a (state, event) pair and the (state, effects) it must produce.
@Suite
struct RealtimeClientTransitionTests {
  typealias State = RealtimeClient.ConnectionState
  typealias Event = RealtimeClient.Event
  typealias Effect = RealtimeClient.Effect

  let socket = FakeWebSocket.fakes().0
  let other = FakeWebSocket.fakes().0

  /// The n-th retry waits n seconds, so every row shows which attempt picked the delay.
  static func retryDelay(_ attempt: Int) -> Duration { .seconds(attempt) }

  static let dropped = RealtimeError.socketClosed(
    code: WebSocketCloseCode(rawValue: 1001), reason: "going away")
  static let unreachable = RealtimeError.transport("unreachable")
  static let refused = RealtimeError.upgradeFailed(status: 401)

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
        from: .disconnected(nil), .connectRequested, to: .connecting(attempt: 1),
        effects: [.openSocket]),
      Row(
        from: .disconnected(Self.refused), .connectRequested, to: .connecting(attempt: 1),
        effects: [.openSocket]),
      Row(
        from: .connecting(attempt: 1), .connectRequested, to: .connecting(attempt: 1), effects: []),
      Row(from: .connected(socket), .connectRequested, to: .connected(socket), effects: []),
      // An explicit connect() skips the rest of the backoff wait.
      Row(
        from: waiting, .connectRequested, to: .connecting(attempt: 3),
        effects: [.cancelRetry, .openSocket]),

      // The transport answered.
      Row(
        from: .connecting(attempt: 1), .socketOpened(socket), to: .connected(socket),
        effects: [.installSocket(socket, rejoinChannels: false)]),
      Row(
        from: .connecting(attempt: 3), .socketOpened(socket), to: .connected(socket),
        effects: [.installSocket(socket, rejoinChannels: true)]),
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
        to: .disconnected(Self.unreachable), effects: []),
      // A failed retry waits longer and tries again.
      Row(
        from: .connecting(attempt: 3), .socketOpenFailed(Self.unreachable),
        to: .reconnecting(attempt: 3, retryIn: .seconds(3), lastError: Self.unreachable),
        effects: [.scheduleRetry(after: .seconds(3))]),
      // A refused upgrade (401/403/404) cannot succeed by retrying.
      Row(
        from: .connecting(attempt: 3), .socketOpenFailed(Self.refused),
        to: .disconnected(Self.refused), effects: []),
      Row(from: waiting, .socketOpenFailed(Self.unreachable), to: waiting, effects: []),
      Row(
        from: .disconnected(nil), .socketOpenFailed(Self.unreachable), to: .disconnected(nil),
        effects: []),

      // The retry timer.
      Row(from: waiting, .retryTimerFired, to: .connecting(attempt: 3), effects: [.openSocket]),
      Row(
        from: .connecting(attempt: 3), .retryTimerFired, to: .connecting(attempt: 3), effects: []),
      Row(from: .connected(socket), .retryTimerFired, to: .connected(socket), effects: []),
      Row(from: .disconnected(nil), .retryTimerFired, to: .disconnected(nil), effects: []),

      // A wake (foreground, network back) only matters while waiting to retry.
      Row(
        from: waiting, .wake, to: .connecting(attempt: 3), effects: [.cancelRetry, .openSocket]),
      Row(from: .connecting(attempt: 1), .wake, to: .connecting(attempt: 1), effects: []),
      Row(from: .connected(socket), .wake, to: .connected(socket), effects: []),
      Row(from: .disconnected(nil), .wake, to: .disconnected(nil), effects: []),

      // disconnect()
      Row(
        from: .connected(socket), .disconnectRequested(code: 1000, reason: "bye"),
        to: .disconnected(nil),
        effects: [.cancelAllTasks, .closeSocket(socket, code: 1000, reason: "bye")]),
      Row(
        from: .connected(socket), .disconnectRequested(code: nil, reason: nil),
        to: .disconnected(nil),
        effects: [.cancelAllTasks, .closeSocket(socket, code: nil, reason: "Client disconnect")]),
      Row(
        from: .connecting(attempt: 1), .disconnectRequested(code: nil, reason: nil),
        to: .disconnected(nil), effects: [.cancelAllTasks]),
      Row(
        from: waiting, .disconnectRequested(code: nil, reason: nil), to: .disconnected(nil),
        effects: [.cancelAllTasks]),
      Row(
        from: .disconnected(Self.refused), .disconnectRequested(code: nil, reason: nil),
        to: .disconnected(nil), effects: [.cancelAllTasks]),

      // The socket went away.
      Row(
        from: .connected(socket), .socketClosed(code: 1001, reason: "going away"),
        to: .reconnecting(attempt: 1, retryIn: .seconds(1), lastError: Self.dropped),
        effects: [.stopSocketLoops, .scheduleRetry(after: .seconds(1))]),
      Row(
        from: .connected(socket), .socketClosed(code: nil, reason: nil),
        to: .reconnecting(
          attempt: 1, retryIn: .seconds(1),
          lastError: .socketClosed(code: nil, reason: nil)),
        effects: [.stopSocketLoops, .scheduleRetry(after: .seconds(1))]),
      // Application close codes (4000–4999) signal auth or protocol errors.
      Row(
        from: .connected(socket), .socketClosed(code: 4001, reason: "jwt expired"),
        to: .disconnected(
          .socketClosed(code: WebSocketCloseCode(rawValue: 4001), reason: "jwt expired")),
        effects: [.stopSocketLoops]),
      Row(
        from: .connected(socket), .socketFailed(.heartbeatTimeout),
        to: .reconnecting(attempt: 1, retryIn: .seconds(1), lastError: .heartbeatTimeout),
        effects: [
          .closeSocket(socket, code: 1001, reason: "error: heartbeat timeout"),
          .stopSocketLoops,
          .scheduleRetry(after: .seconds(1)),
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

      // Channels come and go.
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
      Row(
        from: .connected(socket), .channelAdded, to: .connected(socket),
        effects: [.cancelIdleDisconnect]),
      Row(
        from: .disconnected(nil), .channelAdded, to: .disconnected(nil),
        effects: [.cancelIdleDisconnect]),
    ]
  }

  @Test
  func table() {
    for row in rows {
      var state = row.from
      let effects = RealtimeClient.transition(&state, row.event, retryDelay: Self.retryDelay)
      let location = SourceLocation(
        fileID: #fileID, filePath: #filePath, line: row.line, column: 1)
      #expect(state == row.to, "state after \(row.event)", sourceLocation: location)
      #expect(effects == row.effects, "effects after \(row.event)", sourceLocation: location)
    }
  }

  @Test
  func statusMirrorsThePhase() {
    #expect(State.disconnected(nil).status == .disconnected)
    #expect(State.disconnected(nil).status.error == nil)
    #expect(State.disconnected(Self.refused).status.error?.isSameFailure(as: Self.refused) == true)
    #expect(State.connecting(attempt: 1).status == .connecting)
    #expect(State.connected(socket).status.isConnected)
    guard case .reconnecting(let attempt, let retryIn, let lastError) = waiting.status else {
      Issue.record("Expected .reconnecting, got \(waiting.status)")
      return
    }
    #expect(attempt == 2)
    #expect(retryIn == .seconds(2))
    #expect(lastError.isSameFailure(as: Self.dropped))
  }

  @Test
  func connectedStatesCompareBySocketIdentity() {
    #expect(State.connected(socket) == .connected(socket))
    #expect(State.connected(socket) != .connected(other))
  }

  @Test
  func statesCarryTheirAttemptAndError() {
    #expect(State.connecting(attempt: 1) != .connecting(attempt: 2))
    #expect(State.disconnected(nil) != .disconnected(Self.refused))
    #expect(
      waiting != .reconnecting(attempt: 2, retryIn: .seconds(2), lastError: Self.unreachable))
    #expect(waiting.error?.message == Self.dropped.message)
    #expect(State.disconnected(Self.refused).error?.isRetryable == false)
    #expect(State.connected(socket).error == nil)
  }
}
