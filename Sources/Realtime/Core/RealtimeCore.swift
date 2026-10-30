//
//  RealtimeCore.swift
//  Realtime
//

import Foundation
import Helpers
import Logging

/// The Realtime protocol as a synchronous state machine: the connection, the channels, the refs,
/// and the heartbeat.
///
/// It decides everything and does nothing. ``handle(_:at:)`` updates the state and returns the
/// effects for the shell to run, in order. It has no clock, no tasks, and no continuations, so a
/// test drives it event by event and compares the effects with `==`.
struct RealtimeCore {
  struct Options {
    /// How long a join, a leave, or a push waits for the server's reply.
    var timeout: Duration
    var heartbeatInterval: Duration
    var connectOnSubscribe: Bool
    var disconnectOnEmptyChannelsAfter: Duration
    /// Whether the app set an `accessToken` callback.
    var hasAccessTokenProvider: Bool
    /// The shortest wait between two `accessToken` callback calls.
    var accessTokenRefreshInterval: Duration
    /// How long before the token's `exp` to ask for a new one.
    var accessTokenRefreshLeeway: Duration
    /// The wait after connection attempt `attempt` failed, jitter included.
    var retryDelay: (_ attempt: Int) -> Duration
    /// The wait after join attempt `attempt` failed.
    var rejoinDelay: (_ attempt: Int) -> Duration
    /// The `version` a join sends: the client's `X-Client-Info` header.
    var version: String? = nil
  }

  enum Event {
    // Connection
    /// `connect()` was called. The waiter, if any, is resumed once the attempt ends.
    case connect(waiter: WaiterID?)
    /// The transport handed back an open socket.
    case socketOpened(any WebSocketConnection)
    /// The transport failed to open a socket.
    case socketOpenFailed(RealtimeError)
    /// `disconnect(code:reason:)` was called.
    case disconnectRequested(code: Int?, reason: String?)
    /// The remote closed the current socket.
    case socketClosed(code: Int?, reason: String?)
    /// The current socket failed, for example a heartbeat that was never acknowledged.
    case socketFailed(RealtimeError)
    /// The backoff wait before the next reconnect attempt is over.
    case retryTimerFired
    /// A hint that the network may be back. Cuts a backoff wait short; ignored otherwise.
    case wake
    /// The last channel was removed; disconnect after `disconnectAfter` unless a channel
    /// subscribes first.
    case lastChannelRemoved(disconnectAfter: Duration)
    case appBackground
    case appForeground

    // Commands
    case subscribe(
      topic: String, configuration: RealtimeChannelConfiguration, waiter: WaiterID,
      snapshot: JoinSnapshot)
    case unsubscribe(topic: String, waiter: WaiterID)
    case push(topic: String, event: String, payload: JSONObject, waiter: WaiterID?)
    case broadcast(topic: String, event: String, payload: BroadcastPushPayload, waiter: WaiterID)
    case removeChannel(topic: String, waiter: WaiterID)
    case bindingsChanged(topic: String, snapshot: JoinSnapshot)
    case setAuth(token: String?)

    // Inbound and timers
    case frame(RealtimeMessage)
    case binaryBroadcast(DecodedBroadcast)
    case timerFired(TimerID)
    case tokenFetched(token: String?, generation: Int)
    case waiterCancelled(WaiterID)
  }

  /// What the shell does once the state is updated. Effects run in the order the core emits them.
  enum Effect: Equatable {
    // Connection
    /// Start a connect attempt.
    case openSocket
    /// Start reading the socket. After an automatic reconnect, also rejoin the channels.
    case installSocket(any WebSocketConnection, rejoinChannels: Bool)
    /// Close a socket, either the current one or one that opened too late.
    case closeSocket(any WebSocketConnection, code: Int?, reason: String)
    /// Stop reading the socket that just went away.
    case stopSocketLoops
    /// Cancel every task the client owns, including a connect attempt in flight.
    case cancelAllTasks
    /// Apply `.retryTimerFired` after `after`.
    case scheduleRetry(after: Duration)
    case cancelRetry
    /// Disconnect after `after`.
    case scheduleIdleDisconnect(after: Duration)
    case cancelIdleDisconnect

    /// Write a frame to the current socket.
    case send(RealtimeMessage)
    /// Write a broadcast as a binary frame. `topic` is the wire topic.
    case sendBroadcast(
      joinRef: Ref?, ref: Ref, topic: String, event: String, payload: BroadcastPushPayload)
    /// Apply `.timerFired(id)` after `after`, replacing the pending timer with this id.
    case schedule(TimerID, after: Duration)
    case cancel(TimerID)
    case resume(WaiterID, WaiterOutcome)
    case publishClientStatus(RealtimeClientStatus)
    case publishHeartbeat(HeartbeatEvent)
    /// Publish the status of the channel for a topic.
    case publishChannelStatus(String, RealtimeChannelStatus)
    case deliver(String, Delivery)
    /// End every stream of the channel for a topic.
    case finishChannel(String)
    /// Call the `accessToken` callback and apply `.tokenFetched` with `generation`.
    case fetchAccessToken(generation: Int)

    /// Connections compare by identity, and errors with `isSameFailure(as:)`.
    static func == (lhs: Effect, rhs: Effect) -> Bool {
      switch (lhs, rhs) {
      case (.openSocket, .openSocket), (.stopSocketLoops, .stopSocketLoops),
        (.cancelAllTasks, .cancelAllTasks), (.cancelRetry, .cancelRetry),
        (.cancelIdleDisconnect, .cancelIdleDisconnect):
        return true
      case (.installSocket(let a, let ra), .installSocket(let b, let rb)):
        return a === b && ra == rb
      case (.closeSocket(let a, let ca, let ra), .closeSocket(let b, let cb, let rb)):
        return a === b && ca == cb && ra == rb
      case (.scheduleRetry(let a), .scheduleRetry(let b)),
        (.scheduleIdleDisconnect(let a), .scheduleIdleDisconnect(let b)):
        return a == b
      case (.send(let a), .send(let b)):
        return a == b
      case (
        .sendBroadcast(let ja, let ra, let ta, let ea, let pa),
        .sendBroadcast(let jb, let rb, let tb, let eb, let pb)
      ):
        return ja == jb && ra == rb && ta == tb && ea == eb && pa == pb
      case (.schedule(let a, let da), .schedule(let b, let db)):
        return a == b && da == db
      case (.cancel(let a), .cancel(let b)):
        return a == b
      case (.resume(let a, let oa), .resume(let b, let ob)):
        return a == b && oa == ob
      case (.publishClientStatus(let a), .publishClientStatus(let b)):
        return a.isSame(as: b)
      case (.publishHeartbeat(let a), .publishHeartbeat(let b)):
        return a == b
      case (.publishChannelStatus(let ta, let a), .publishChannelStatus(let tb, let b)):
        return ta == tb && a.isSame(as: b)
      case (.deliver(let ta, let a), .deliver(let tb, let b)):
        return ta == tb && a == b
      case (.finishChannel(let a), .finishChannel(let b)):
        return a == b
      case (.fetchAccessToken(let a), .fetchAccessToken(let b)):
        return a == b
      default:
        return false
      }
    }
  }

  let options: Options
  let logger: Logger

  // Read-only outside the core. Not `private(set)`: the core's extensions in other files write
  // them, and Swift has no setter access level for that.
  var connection: RealtimeClient.ConnectionState = .disconnected(nil)
  var channels: [String: ChannelRecord] = [:]

  var tokens = TokenState()
  /// The last ref ``makeRef()`` made.
  var lastRef: UInt64 = 0
  var heartbeat = HeartbeatState()
  /// The `connect()` callers waiting for the attempt in flight.
  var connectWaiters: [WaiterID] = []
  /// Whether the socket was connected when the app last went to the background.
  var wasConnectedBeforeBackground = false
  /// Whether an idle disconnect is scheduled, so the next `subscribe` cancels it.
  var idleDisconnectPending = false

  init(options: Options, logger: Logger, initialToken: String?) {
    self.options = options
    self.logger = logger
    _ = tokens.apply(initialToken, generation: tokens.generation)
  }

  /// A new message ref: `"1"`, `"2"`, … A disconnect starts the count again.
  mutating func makeRef() -> Ref {
    lastRef += 1
    return lastRef.description
  }

  mutating func handle(_ event: Event, at time: CoreTime) -> [Effect] {
    switch event {
    case .connect(let waiter):
      return connect(waiter: waiter)
    case .socketOpened, .socketOpenFailed:
      let previous = connection
      let effects = transitionConnection(event)
      return connection == previous ? effects : effects + connectAttemptEnded()
    case .disconnectRequested, .socketClosed, .socketFailed, .retryTimerFired, .wake,
      .lastChannelRemoved:
      return transitionConnection(event)
    case .appBackground:
      return enterBackground()
    case .appForeground:
      return enterForeground()
    case .timerFired(.heartbeat):
      return heartbeatTimerFired(at: time)
    case .frame(let message) where message.topic == "phoenix":
      return receiveHeartbeatReply(message, at: time)
    case .frame(let message) where message.event == ChannelEvent.system:
      return receiveSystem(message)
    case .frame(let message):
      return receiveJoinReply(message)

    case .subscribe(let topic, let configuration, let waiter, let snapshot):
      return subscribe(
        topic: topic, configuration: configuration, waiter: waiter, snapshot: snapshot)
    case .timerFired(.joinTimeout(let topic, let ref)):
      return joinTimedOut(topic, ref: ref)
    case .timerFired(.rejoin(let topic)):
      return rejoinTimerFired(topic)
    case .timerFired(.postgresTimeout(let topic, let ref)):
      return postgresTimedOut(topic, ref: ref)
    case .bindingsChanged(let topic, let snapshot):
      return bindingsChanged(topic, snapshot: snapshot)

    // Not handled yet: the other channel commands, frames and timers, tokens, and waiter
    // cancellation.
    case .unsubscribe, .push, .broadcast, .removeChannel, .setAuth, .binaryBroadcast, .timerFired,
      .tokenFetched, .waiterCancelled:
      return []
    }
  }
}
