//
//  ConnectionMachineTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 06/10/26.
//

import Testing

@testable import Realtime

@Suite
struct ConnectionMachineTests {
  typealias State = ConnectionMachine.State
  typealias Event = ConnectionMachine.Event
  typealias Effect = ConnectionMachine.Effect

  /// A comparable view of a state. `RealtimeError` is not `Equatable`, so rows compare the
  /// case and whether it carries an error.
  enum Shape: Equatable {
    case disconnected(hasError: Bool)
    case connecting(attempt: Int)
    case connected
    case reconnecting(attempt: Int, retryIn: Duration)

    init(_ state: State) {
      switch state {
      case .disconnected(let error): self = .disconnected(hasError: error != nil)
      case .connecting(let attempt): self = .connecting(attempt: attempt)
      case .connected: self = .connected
      case .reconnecting(let attempt, let retryIn, _):
        self = .reconnecting(attempt: attempt, retryIn: retryIn)
      }
    }
  }

  struct Row: CustomTestStringConvertible {
    let name: String
    let from: State
    let event: Event
    let to: Shape
    let effects: [Effect]
    var testDescription: String { name }
  }

  static let configuration = ConnectionMachine.Configuration(
    reconnect: .steps([.seconds(1), .seconds(2), .seconds(5)]),
    idleDisconnectAfter: .seconds(50)
  )

  static let fatal = RealtimeError.upgradeFailed(status: 401)
  static let transient = RealtimeError.upgradeFailed(status: 503)
  static let lost = RealtimeError.socketClosed(code: .abnormalClosure, reason: nil)
  static let reconnecting = State.reconnecting(attempt: 2, retryIn: .seconds(2), lastError: lost)

  static let rows: [Row] = [
    // §9.1 connect
    Row(
      name: "connect from idle opens the transport",
      from: .disconnected(nil), event: .connectRequested,
      to: .connecting(attempt: 1), effects: [.openTransport]),
    Row(
      name: "connect after a fatal error tries again",
      from: .disconnected(fatal), event: .connectRequested,
      to: .connecting(attempt: 1), effects: [.openTransport]),
    Row(
      name: "resume from paused opens the transport",
      from: .disconnected(nil), event: .resumeRequested,
      to: .connecting(attempt: 1), effects: [.openTransport]),
    Row(
      name: "connect while connecting is a no-op",
      from: .connecting(attempt: 1), event: .connectRequested,
      to: .connecting(attempt: 1), effects: []),
    Row(
      name: "connect while connected is a no-op",
      from: .connected, event: .connectRequested,
      to: .connected, effects: []),
    // upgrade
    Row(
      name: "upgrade ok starts the heartbeat and rejoins every channel",
      from: .connecting(attempt: 3), event: .upgradeSucceeded,
      to: .connected, effects: [.startHeartbeat, .rejoinAllChannels]),
    Row(
      name: "upgrade 401 ends in disconnected with the error and no retry",
      from: .connecting(attempt: 1), event: .upgradeFailed(fatal),
      to: .disconnected(hasError: true), effects: [.channelsSocketLost]),
    Row(
      name: "upgrade 503 schedules the first retry",
      from: .connecting(attempt: 1), event: .upgradeFailed(transient),
      to: .reconnecting(attempt: 1, retryIn: .seconds(1)),
      effects: [.scheduleRetry(after: .seconds(1))]),
    Row(
      name: "a later failed attempt uses the next backoff step",
      from: .connecting(attempt: 3), event: .upgradeFailed(transient),
      to: .reconnecting(attempt: 3, retryIn: .seconds(5)),
      effects: [.scheduleRetry(after: .seconds(5))]),
    Row(
      name: "attempts are unlimited and stay on the last step",
      from: .connecting(attempt: 40), event: .upgradeFailed(transient),
      to: .reconnecting(attempt: 40, retryIn: .seconds(5)),
      effects: [.scheduleRetry(after: .seconds(5))]),
    Row(
      name: "a close during the handshake retries",
      from: .connecting(attempt: 1), event: .transportClosed(code: nil, reason: nil),
      to: .reconnecting(attempt: 1, retryIn: .seconds(1)),
      effects: [.scheduleRetry(after: .seconds(1))]),
    // loss while connected
    Row(
      name: "transport closed while connected fails replies and reconnects",
      from: .connected, event: .transportClosed(code: .abnormalClosure, reason: "x"),
      to: .reconnecting(attempt: 1, retryIn: .seconds(1)),
      effects: [
        .stopHeartbeat, .failPendingReplies, .channelsSocketLost,
        .scheduleRetry(after: .seconds(1)),
      ]),
    Row(
      name: "heartbeat timeout closes the transport then reconnects",
      from: .connected, event: .heartbeatTimedOut,
      to: .reconnecting(attempt: 1, retryIn: .seconds(1)),
      effects: [
        .stopHeartbeat, .closeTransport(code: .normalClosure), .failPendingReplies,
        .channelsSocketLost, .scheduleRetry(after: .seconds(1)),
      ]),
    Row(
      name: "the close that follows a heartbeat timeout is ignored",
      from: reconnecting, event: .transportClosed(code: .normalClosure, reason: nil),
      to: .reconnecting(attempt: 2, retryIn: .seconds(2)), effects: []),
    // retry
    Row(
      name: "retry timer opens the transport with the next attempt",
      from: reconnecting, event: .retryTimerFired,
      to: .connecting(attempt: 3), effects: [.openTransport]),
    Row(
      name: "a wake signal while reconnecting retries at once",
      from: reconnecting, event: .wakeSignal,
      to: .connecting(attempt: 3), effects: [.cancelRetry, .openTransport]),
    Row(
      name: "connect while reconnecting retries at once",
      from: reconnecting, event: .connectRequested,
      to: .connecting(attempt: 3), effects: [.cancelRetry, .openTransport]),
    Row(
      name: "a wake signal while connected is a no-op",
      from: .connected, event: .wakeSignal, to: .connected, effects: []),
    Row(
      name: "a wake signal while disconnected is a no-op",
      from: .disconnected(nil), event: .wakeSignal,
      to: .disconnected(hasError: false), effects: []),
    // disconnect / pause
    Row(
      name: "disconnect while connected leaves channels and closes normally",
      from: .connected, event: .disconnectRequested,
      to: .disconnected(hasError: false),
      effects: [
        .stopHeartbeat, .cancelIdleDisconnect, .channelsUnsubscribed,
        .closeTransport(code: .normalClosure), .failPendingReplies,
      ]),
    Row(
      name: "disconnect while reconnecting cancels the retry",
      from: reconnecting, event: .disconnectRequested,
      to: .disconnected(hasError: false), effects: [.cancelRetry, .channelsUnsubscribed]),
    Row(
      name: "disconnect while connecting abandons the handshake",
      from: .connecting(attempt: 1), event: .disconnectRequested,
      to: .disconnected(hasError: false),
      effects: [.closeTransport(code: .normalClosure), .channelsUnsubscribed]),
    Row(
      name: "disconnect while disconnected is a no-op",
      from: .disconnected(fatal), event: .disconnectRequested,
      to: .disconnected(hasError: false), effects: []),
    Row(
      name: "pause while connected keeps channels wanting to subscribe",
      from: .connected, event: .pauseRequested,
      to: .disconnected(hasError: false),
      effects: [
        .stopHeartbeat, .cancelIdleDisconnect, .channelsSocketLost,
        .closeTransport(code: .normalClosure), .failPendingReplies,
      ]),
    Row(
      name: "pause while reconnecting cancels the retry",
      from: reconnecting, event: .pauseRequested,
      to: .disconnected(hasError: false), effects: [.cancelRetry]),
    // idle
    Row(
      name: "last channel removed schedules the idle disconnect",
      from: .connected, event: .lastChannelRemoved,
      to: .connected, effects: [.scheduleIdleDisconnect(after: .seconds(50))]),
    Row(
      name: "a new channel cancels the idle disconnect",
      from: .connected, event: .channelAdded,
      to: .connected, effects: [.cancelIdleDisconnect]),
    Row(
      name: "idle timer disconnects like the user did",
      from: .connected, event: .idleTimerFired,
      to: .disconnected(hasError: false),
      effects: [
        .stopHeartbeat, .cancelIdleDisconnect, .channelsUnsubscribed,
        .closeTransport(code: .normalClosure), .failPendingReplies,
      ]),
    Row(
      name: "idle events while disconnected are no-ops",
      from: .disconnected(nil), event: .lastChannelRemoved,
      to: .disconnected(hasError: false), effects: []),
    // stale timers
    Row(
      name: "a stale retry timer while connected is a no-op",
      from: .connected, event: .retryTimerFired, to: .connected, effects: []),
    Row(
      name: "a stale upgrade result while disconnected is a no-op",
      from: .disconnected(nil), event: .upgradeSucceeded,
      to: .disconnected(hasError: false), effects: []),
  ]

  @Test(arguments: rows)
  func transition(row: Row) {
    var state = row.from

    let effects = ConnectionMachine.transition(&state, row.event, configuration: Self.configuration)

    #expect(Shape(state) == row.to)
    #expect(effects == row.effects)
  }

  @Test
  func retryableFailureKeepsTheErrorAndFatalFailureExposesIt() {
    var state = State.connecting(attempt: 1)
    _ = ConnectionMachine.transition(
      &state, .upgradeFailed(Self.transient), configuration: Self.configuration)
    #expect(state.error?.message.contains("503") == true)
    #expect(!state.isConnected)

    state = .connecting(attempt: 1)
    _ = ConnectionMachine.transition(
      &state, .upgradeFailed(Self.fatal), configuration: Self.configuration)
    #expect(state.error?.isRetryable == false)
  }

  @Test
  func transportClosedWhileConnectedRecordsTheCloseCode() {
    var state = State.connected
    _ = ConnectionMachine.transition(
      &state, .transportClosed(code: WebSocketCloseCode(rawValue: 4000), reason: "kicked"),
      configuration: Self.configuration)

    #expect(state.error?.closeCode == WebSocketCloseCode(rawValue: 4000))
    #expect(state.error?.message.contains("kicked") == true)
  }

  @Test
  func connectedIsTheOnlyConnectedState() {
    #expect(State.connected.isConnected)
    #expect(!State.connecting(attempt: 1).isConnected)
    #expect(!State.disconnected(nil).isConnected)
    #expect(!Self.reconnecting.isConnected)
    #expect(State.connected.error == nil)
  }
}
