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

  var rows: [Row] {
    [
      // connect()
      Row(from: .disconnected, .connectRequested, to: .connecting, effects: [.openSocket]),
      Row(from: .connecting, .connectRequested, to: .connecting, effects: []),
      Row(from: .connected(socket), .connectRequested, to: .connected(socket), effects: []),
      Row(from: .reconnecting, .connectRequested, to: .reconnecting, effects: []),

      // The transport answered.
      Row(
        from: .connecting, .socketOpened(socket), to: .connected(socket),
        effects: [.installSocket(socket, rejoinChannels: false)]),
      Row(
        from: .reconnecting, .socketOpened(socket), to: .connected(socket),
        effects: [.installSocket(socket, rejoinChannels: true)]),
      Row(
        from: .disconnected, .socketOpened(socket), to: .disconnected,
        effects: [.closeSocket(socket, code: nil, reason: "Connection cancelled")]),
      Row(
        from: .connected(socket), .socketOpened(other), to: .connected(socket),
        effects: [.closeSocket(other, code: nil, reason: "Connection cancelled")]),
      Row(from: .connecting, .socketOpenFailed, to: .disconnected, effects: []),
      Row(from: .reconnecting, .socketOpenFailed, to: .reconnecting, effects: []),
      Row(from: .disconnected, .socketOpenFailed, to: .disconnected, effects: []),

      // disconnect()
      Row(
        from: .connected(socket), .disconnectRequested(code: 1000, reason: "bye"),
        to: .disconnected,
        effects: [.cancelAllTasks, .closeSocket(socket, code: 1000, reason: "bye")]),
      Row(
        from: .connected(socket), .disconnectRequested(code: nil, reason: nil),
        to: .disconnected,
        effects: [.cancelAllTasks, .closeSocket(socket, code: nil, reason: "Client disconnect")]),
      Row(
        from: .connecting, .disconnectRequested(code: nil, reason: nil), to: .disconnected,
        effects: [.cancelAllTasks]),
      Row(
        from: .reconnecting, .disconnectRequested(code: nil, reason: nil), to: .disconnected,
        effects: [.cancelAllTasks]),
      Row(
        from: .disconnected, .disconnectRequested(code: nil, reason: nil), to: .disconnected,
        effects: [.cancelAllTasks]),

      // The socket went away.
      Row(
        from: .connected(socket), .socketClosed(code: 1001, reason: "going away"),
        to: .reconnecting,
        effects: [.stopSocketLoops, .startReconnect(reason: "code: 1001, reason: going away")]),
      Row(
        from: .connected(socket), .socketClosed(code: nil, reason: nil), to: .reconnecting,
        effects: [.stopSocketLoops, .startReconnect(reason: "code: none, reason: none")]),
      Row(
        from: .connected(socket), .socketClosed(code: 4001, reason: "jwt expired"),
        to: .disconnected, effects: [.stopSocketLoops]),
      Row(
        from: .connected(socket), .socketFailed(reason: "heartbeat timeout"), to: .reconnecting,
        effects: [
          .closeSocket(socket, code: 1001, reason: "error: heartbeat timeout"),
          .stopSocketLoops,
          .startReconnect(reason: "error: heartbeat timeout"),
        ]),
      Row(from: .connecting, .socketClosed(code: 1001, reason: nil), to: .connecting, effects: []),
      Row(
        from: .reconnecting, .socketClosed(code: 1001, reason: nil), to: .reconnecting, effects: []),
      Row(
        from: .disconnected, .socketClosed(code: 1001, reason: nil), to: .disconnected, effects: []),
      Row(from: .connecting, .socketFailed(reason: "x"), to: .connecting, effects: []),
      Row(from: .reconnecting, .socketFailed(reason: "x"), to: .reconnecting, effects: []),
      Row(from: .disconnected, .socketFailed(reason: "x"), to: .disconnected, effects: []),
    ]
  }

  @Test
  func table() {
    for row in rows {
      var state = row.from
      let effects = RealtimeClient.transition(&state, row.event)
      let location = SourceLocation(
        fileID: #fileID, filePath: #filePath, line: row.line, column: 1)
      #expect(state == row.to, "state after \(row.event)", sourceLocation: location)
      #expect(effects == row.effects, "effects after \(row.event)", sourceLocation: location)
    }
  }

  @Test
  func statusMirrorsThePhase() {
    #expect(State.disconnected.status == .disconnected)
    #expect(State.connecting.status == .connecting)
    #expect(State.reconnecting.status == .connecting)
    #expect(State.connected(socket).status == .connected)
  }

  @Test
  func connectedStatesCompareBySocketIdentity() {
    #expect(State.connected(socket) == .connected(socket))
    #expect(State.connected(socket) != .connected(other))
  }
}
