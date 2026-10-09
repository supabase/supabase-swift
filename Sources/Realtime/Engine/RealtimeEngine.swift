//
//  RealtimeEngine.swift
//  Realtime
//
//  Created by Guilherme Souza on 06/10/26.
//

import ConcurrencyExtras
package import Foundation
package import HTTPTypes
package import Helpers
package import Logging

/// What a channel listener receives.
package enum ChannelInbound: Sendable {
  /// A text-frame message on the topic: broadcast, presence, postgres changes, system.
  case message(RealtimeMessageV2)
  /// A kind-4 binary broadcast.
  case broadcast(DecodedBroadcast)
  /// The channel rejoined; events may have been missed in between.
  case resubscribed
  /// The presence set changed, after a `presence_state` or `presence_diff`. `state` is the
  /// whole set after the change.
  case presenceChanged(PresenceChange, state: PresenceState)
}

/// The identity of one channel handle. Engine calls that create, join or remove channel state
/// only act for the owner of the topic's record, and a retired owner can never create one, so a
/// removed handle cannot touch the channel that replaced it.
package final class ChannelOwner: Sendable {
  package let id = UUID()
  private let retired = LockIsolated(false)

  package init() {}

  /// Whether the handle was removed from its client.
  package var isRetired: Bool { retired.value }

  package func retire() {
    retired.setValue(true)
  }
}

package struct RealtimeEngineConfiguration: Sendable {
  package var url: URL
  package var headers: HTTPFields = [:]
  package var heartbeatInterval: Duration = .seconds(25)
  package var heartbeatTimeout: Duration = .seconds(10)
  /// How long a join, leave or acknowledged push waits for its reply.
  package var timeout: Duration = .seconds(15)
  package var connectTimeout: Duration = .seconds(15)
  package var connectOnSubscribe = true
  package var connection = ConnectionMachine.Configuration(
    reconnect: .fullJitter(base: .seconds(1), cap: .seconds(30)),
    idleDisconnectAfter: .seconds(50))
  package var channel = ChannelMachine.Configuration(
    rejoin: .steps([.seconds(1), .seconds(2), .seconds(5), .seconds(10)]),
    rateLimitBackoff: .seconds(30),
    lingerAfterLastListener: .seconds(2))
  package var accessToken: (@Sendable () async throws -> String?)?
  /// The token joins carry until the provider or `setAuth(_:)` gives another.
  package var initialAccessToken: String?
  /// How long before the token's `exp` the engine asks the provider for a fresh one.
  package var accessTokenRefreshLeeway: Duration = .seconds(60)
  /// The shortest wait between two provider calls, so a token already inside the leeway, or a
  /// failed refresh, is retried at this pace instead of in a tight loop.
  package var accessTokenRetryInterval: Duration = .seconds(5)
  /// The server applies at most one `access_token` per channel in this window.
  package var accessTokenPushInterval: Duration = .seconds(10)
  /// The server allows 5 presence calls per 30 s per channel; one call per window stays under.
  package var presenceTrackInterval: Duration = .seconds(6)
  package var logger = supabaseDefaultLogger(label: "io.supabase.realtime")

  package init(url: URL) {
    self.url = url
  }
}

/// ``EngineState`` behind a lock, changed in place.
///
/// The rest of the SDK uses `LockIsolated`, but it copies the value out and back on every call:
/// the first change to each dictionary in `EngineState` would copy the whole dictionary, and a
/// re-entrant call would silently drop the inner write. The lock is recursive only so that a
/// re-entrant call reaches the `precondition` and traps with a message instead of deadlocking.
private final class EngineStateLock: @unchecked Sendable {
  private let lock = NSRecursiveLock()
  private var state: EngineState
  private var isLocked = false

  init(_ state: EngineState) {
    self.state = state
  }

  func withLock<T>(_ body: (inout EngineState) -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    precondition(!isLocked, "RealtimeEngine.withState re-entered under its own lock")
    isLocked = true
    defer { isLocked = false }
    return body(&state)
  }
}

/// The one mutable core of Realtime: one socket, one supervisor task, pure machines for the
/// connection and every channel, and fan-out to listeners.
///
/// All mutable state is one ``EngineState`` behind one lock. Synchronous reads and stream
/// registration take the lock directly; socket, timer and reply tasks take it to apply an event,
/// then run the deferred work outside it. Nothing awaits under the lock, so there is no
/// suspension point between a check and the change it guards.
package final class RealtimeEngine: Sendable {
  private enum Gate: Sendable {
    /// Wait for the channel's next subscribe outcome.
    case wait
    case done
    /// Wait for the acknowledgement of this ref.
    case ack(String)
  }

  private enum SupervisorStep: Sendable {
    case attempt
    case sleep(Duration)
    case stop
  }

  private let configuration: RealtimeEngineConfiguration
  private let transport: any WebSocketTransport
  let clock: any Clock<Duration>
  private let serializer = RealtimeSerializer()
  let logger: Logger
  private let state: EngineStateLock

  package init(
    configuration: RealtimeEngineConfiguration,
    transport: any WebSocketTransport,
    clock: any Clock<Duration> = ContinuousClock()
  ) {
    self.configuration = configuration
    self.transport = transport
    self.clock = clock
    self.logger = configuration.logger
    state = EngineStateLock(EngineState(configuration: configuration, clock: clock))
    withState { state in
      state.engine = self
      let generation = state.tokens.beginRefresh()
      _ = state.tokens.apply(configuration.initialAccessToken, generation: generation)
    }
  }

  /// Runs `body` under the lock, then the work it deferred, outside the lock.
  @discardableResult
  func withState<T: Sendable, E: Error>(
    _ body: @Sendable (inout EngineState) throws(E) -> T
  ) throws(E) -> T {
    let (result, deferred) = state.withLock { state in
      let result = Result { () throws(E) -> T in try body(&state) }
      return (result, state.takeDeferred())
    }
    for work in deferred { work() }
    return try result.get()
  }

  // MARK: - Connection API

  package var connectionState: ConnectionMachine.State { withState { $0.connection } }

  package var connectionStatus: RealtimeConnectionStatus {
    withState { $0.connection.publicStatus }
  }

  /// Returns once the socket is connected. Throws the fatal error when the upgrade is refused
  /// for good (401, 403, 404), `.notConnected` when `disconnect()` wins the race, and
  /// `CancellationError` when the calling task is cancelled; the socket keeps connecting.
  package func connect() async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        withState { state in
          switch state.connection {
          case .connected:
            state.later { continuation.resume() }
            return
          case .disconnected, .reconnecting: state.applyConnection(.connectRequested)
          case .connecting: break
          }
          if Task.isCancelled {
            state.later { continuation.resume(throwing: CancellationError()) }
          } else {
            state.connectWaiters[id] = continuation
            state.resolveConnectWaiters()
          }
        }
      }
    } onCancel: {
      withState { state in
        guard let waiter = state.connectWaiters.removeValue(forKey: id) else { return }
        state.later { waiter.resume(throwing: CancellationError()) }
      }
    }
  }

  /// Leaves every channel, closes the socket, and returns once it is closed.
  package func disconnect() async {
    let supervisor = withState { state in
      state.applyConnection(.disconnectRequested)
      return state.supervisor
    }
    await supervisor?.value
  }

  /// Closes the socket but keeps every channel wanting its subscription.
  package func pause() async {
    let supervisor = withState { state in
      state.applyConnection(.pauseRequested)
      return state.supervisor
    }
    await supervisor?.value
  }

  /// Reconnects after `pause()` and rejoins every channel that was subscribed.
  package func resume() async {
    withState { state in
      if case .disconnected = state.connection { state.applyConnection(.resumeRequested) }
    }
    try? await connect()
  }

  /// The network path became satisfied or the app came to the foreground.
  package func wake() {
    withState { $0.applyConnection(.wakeSignal) }
  }

  /// Stops the engine for good without waiting: finishes every stream, cancels the supervisor and
  /// closes the socket.
  /// The supervisor then moves the engine to `.disconnected`, and a later connect ends there
  /// at once. For a `deinit`, which cannot await.
  package func shutdown() {
    let (supervisor, socket) = withState { state in
      state.shutDown()
      return (state.supervisor, state.socket)
    }
    supervisor?.cancel()
    if let socket {
      Task { await socket.close(code: .normalClosure, reason: nil) }
    }
  }

  /// The token joins carry: the last one `setAuth(_:)` or the provider gave.
  package var accessToken: String? { withState { $0.tokens.token } }

  var pendingReplyCount: Int { withState { $0.pendingReplies.count } }

  /// Makes a stream and registers it in one critical section, or finishes it when `register`
  /// returns `false`. The finish runs outside the lock, since it calls `onTermination`.
  private func listen<Element: Sendable>(
    _ policy: AsyncStream<Element>.Continuation.BufferingPolicy,
    register: @Sendable (inout EngineState, UUID, AsyncStream<Element>.Continuation) -> Bool,
    unregister: @escaping @Sendable (inout EngineState, UUID) -> Void
  ) -> AsyncStream<Element> {
    let (stream, continuation) = AsyncStream<Element>.makeStream(bufferingPolicy: policy)
    let id = UUID()
    continuation.onTermination = { [weak self] _ in self?.withState { unregister(&$0, id) } }
    if !withState({ register(&$0, id, continuation) }) { continuation.finish() }
    return stream
  }

  package func connectionStates() -> AsyncStream<ConnectionMachine.State> {
    listen(.bufferingNewest(1)) { state, id, continuation in
      state.connectionStates[id] = continuation
      return true
    } unregister: { state, id in
      state.connectionStates[id] = nil
    }
  }

  /// The socket's status, starting with the current one, keeping only the newest. Registers
  /// before it returns.
  package func connectionStatuses() -> AsyncStream<RealtimeConnectionStatus> {
    listen(.bufferingNewest(1)) { state, id, continuation in
      guard !state.isShutDown else {
        continuation.yield(.disconnected(nil))
        return false
      }
      continuation.yield(state.connection.publicStatus)
      state.connectionStatuses[id] = continuation
      return true
    } unregister: { state, id in
      state.connectionStatuses[id] = nil
    }
  }

  /// Every heartbeat step, unbounded so a latency display misses none. Registers before it
  /// returns.
  package func heartbeats() -> AsyncStream<HeartbeatEvent> {
    listen(.unbounded) { state, id, continuation in
      guard !state.isShutDown else { return false }
      state.heartbeats[id] = continuation
      return true
    } unregister: { state, id in
      state.heartbeats[id] = nil
    }
  }

  // MARK: - Channel API

  /// Adds the channel, or replaces the config of the owner's channel. The new config goes out
  /// with the next join.
  ///
  /// When a retired owner still holds the topic, this waits until its removal finishes, then
  /// installs a fresh record. A retired `owner`, or a topic another live owner holds, is a no-op.
  package func addChannel(
    _ topic: String, owner: ChannelOwner, config: RealtimeJoinConfig = RealtimeJoinConfig()
  ) async {
    while await withCheckedContinuation({ (continuation: CheckedContinuation<Bool, Never>) in
      withState { state in
        if let record = state.channels[topic], record.owner !== owner, record.owner.isRetired,
          !owner.isRetired
        {
          state.removalWaiters[topic, default: []].append(continuation)
        } else {
          state.install(topic, owner: owner, config: config)
          state.later { continuation.resume(returning: false) }
        }
      }
    }) {}
  }

  /// Replaces the channel's postgres bindings. A joined or joining channel joins again with them.
  ///
  /// A channel only adds bindings, and each addition sends its snapshot from its own task, so a
  /// list no longer than the current one is unchanged or stale and is ignored.
  package func updateBindings(
    _ topic: String, owner: ChannelOwner, _ bindings: [PostgresJoinConfig]
  ) {
    withState { state in
      guard let record = state.channels[topic], record.owner === owner,
        bindings.count > record.config.postgresChanges.count
      else { return }
      state.channels[topic]?.config.postgresChanges = bindings
      state.applyChannel(topic, .bindingsChanged)
    }
  }

  /// Leaves and forgets the owner's channel, and finishes every stream of `owner`.
  package func removeChannel(_ topic: String, owner: ChannelOwner) async {
    let isOwner = withState { state in
      guard state.isOwner(owner, of: topic) else {
        state.dropListeners(topic, owner: owner.id)
        return false
      }
      return true
    }
    guard isOwner else { return }
    await leave(topic)
    withState { $0.forget(topic, owner: owner) }
  }

  package func channelState(_ topic: String) -> ChannelMachine.State? {
    withState { $0.channels[topic]?.state }
  }

  /// `.unsubscribed` unless `owner` holds the topic's record.
  package func channelStatus(_ topic: String, owner: ChannelOwner) -> RealtimeChannelStatus {
    withState { state in
      guard let record = state.channels[topic], record.owner === owner else { return .unsubscribed }
      return record.state.publicStatus
    }
  }

  /// The server ids of the channel's postgres bindings, by position, from the last join.
  package func postgresChangeIDs(_ topic: String) -> [Int] {
    withState { $0.channels[topic]?.postgresChangeIDs ?? [] }
  }

  /// Returns once the join is acknowledged. Throws the server's reason for a fatal join error,
  /// `.notSubscribed` when the channel is unsubscribed before the join completes, and
  /// `CancellationError` when the calling task is cancelled; the channel keeps joining.
  package func subscribe(_ topic: String, owner: ChannelOwner) async throws {
    _ = try await gate(topic) { state in
      guard state.isOwner(owner, of: topic) else {
        throw RealtimeError(
          kind: .notSubscribed,
          message: owner.isRetired
            ? "channel \(topic) was removed" : "unknown channel \(topic)")
      }
      state.applyChannel(topic, .subscribeRequested)
      return state.channels[topic]?.state.isSubscribed == true ? .done : .wait
    }
  }

  /// Runs `decide` under the lock. On `.wait` it parks the caller on the channel's next
  /// `resolveSubscribe` or `rejectSubscribe` in the same critical section, so a join that
  /// completes right after `decide` still reaches it. Returns the ref of an `.ack`.
  private func gate(
    _ topic: String, _ decide: @Sendable (inout EngineState) throws -> Gate
  ) async throws -> String? {
    let id = UUID()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<String?, any Error>) in
        withState { state in
          let gate: Gate
          do {
            gate = try decide(&state)
          } catch {
            state.later { continuation.resume(throwing: error) }
            return
          }
          switch gate {
          case .done:
            state.later { continuation.resume(returning: nil) }
          case .ack(let ref):
            state.later { continuation.resume(returning: ref) }
          case .wait:
            if Task.isCancelled {
              state.later { continuation.resume(throwing: CancellationError()) }
            } else if state.channels[topic] == nil {
              state.later {
                continuation.resume(
                  throwing: RealtimeError(
                    kind: .notSubscribed, message: "channel \(topic) was removed"))
              }
            } else {
              state.channels[topic]?.subscribeWaiters[id] = continuation
            }
          }
        }
      }
    } onCancel: {
      withState { state in
        guard let waiter = state.channels[topic]?.subscribeWaiters.removeValue(forKey: id)
        else { return }
        state.later { waiter.resume(throwing: CancellationError()) }
      }
    }
  }

  /// Sends the leave and returns once the server replied, the reply timed out, or the socket
  /// was already gone.
  package func unsubscribe(_ topic: String, owner: ChannelOwner) async {
    guard withState({ $0.isOwner(owner, of: topic) }) else { return }
    await leave(topic)
  }

  private func leave(_ topic: String) async {
    let ref = await withCheckedContinuation { continuation in
      withState { $0.beginLeave(topic, continuation) }
    }
    guard let ref else { return }
    _ = try? await withTimeout(configuration.timeout, clock: clock) {
      try await self.waitForReply(ref)
    }
    withState { $0.applyChannel(topic, .leaveCompleted) }
  }

  package func channelStates(_ topic: String) -> AsyncStream<ChannelMachine.State> {
    listen(.bufferingNewest(1)) { state, id, continuation in
      state.channelStates[topic, default: [:]][id] = continuation
      return true
    } unregister: { state, id in
      state.channelStates[topic]?[id] = nil
    }
  }

  /// The channel's status, starting with the current one, keeping only the newest. Registers
  /// before it returns. For a retired owner, or after shutdown, it yields `.unsubscribed` and
  /// ends.
  package func channelStatuses(_ topic: String, owner: ChannelOwner)
    -> AsyncStream<RealtimeChannelStatus>
  {
    let key = EngineState.ListenerKey(topic: topic, owner: owner.id)
    return listen(.bufferingNewest(1)) { state, id, continuation in
      guard !state.isShutDown, !owner.isRetired else {
        continuation.yield(.unsubscribed)
        return false
      }
      let record = state.channels[topic]
      continuation.yield(record?.owner === owner ? record!.state.publicStatus : .unsubscribed)
      state.channelStatuses[key, default: [:]][id] = continuation
      return true
    } unregister: { state, id in
      state.channelStatuses[key]?[id] = nil
    }
  }

  /// Every message `owner` receives on the topic, unbounded. Registers before it returns; ending
  /// the iteration removes the listener. For a retired owner, or after shutdown, it ends at once.
  package func inbound(_ topic: String, owner: ChannelOwner) -> AsyncStream<ChannelInbound> {
    let key = EngineState.ListenerKey(topic: topic, owner: owner.id)
    return listen(.unbounded) { state, id, continuation in
      guard !state.isShutDown, !owner.isRetired else { return false }
      state.inbound[key, default: [:]][id] = continuation
      return true
    } unregister: { state, id in
      state.inbound[key]?[id] = nil
      if state.inbound[key]?.isEmpty == true { state.inbound[key] = nil }
    }
  }

  /// The live owner's listeners on the topic.
  package func listenerCount(_ topic: String) -> Int {
    withState { state in state.liveKey(topic).flatMap { state.inbound[$0]?.count } ?? 0 }
  }

  /// Sends a push on a subscribed channel. With `awaitReply` it returns the reply payload, or
  /// throws `.timeout`, `.notConnected` when the socket goes away first, or the server's ack
  /// error.
  @discardableResult
  package func send(
    _ topic: String, owner: ChannelOwner, event: String, payload: JSONObject, awaitReply: Bool
  ) async throws -> JSONObject? {
    let ref = try withState { state throws -> String? in
      let joinRef = try state.joinRefForPush(topic, owner: owner)
      let ref = state.makeRef()
      let message = RealtimeMessageV2(
        joinRef: joinRef, ref: ref, topic: topic, event: event, payload: payload)
      try state.enqueue(.text(try state.serializer.encodeText(message)))
      guard awaitReply else { return nil }
      state.expectReply(ref)
      return ref
    }
    guard let ref else { return nil }
    return try await awaitAcknowledgement(ref: ref)
  }

  /// Sends a kind-3 binary broadcast on a subscribed channel.
  package func sendBroadcast(
    _ topic: String, owner: ChannelOwner, event: String, data: Data, awaitReply: Bool = false
  ) async throws {
    let ref = try withState { state throws -> String? in
      let joinRef = try state.joinRefForPush(topic, owner: owner)
      let ref = state.makeRef()
      let frame = try state.serializer.encodeBroadcastPush(
        joinRef: joinRef, ref: ref, topic: topic, event: event, binaryPayload: data)
      try state.enqueue(.binary(frame))
      guard awaitReply else { return nil }
      state.expectReply(ref)
      return ref
    }
    guard let ref else { return }
    _ = try await awaitAcknowledgement(ref: ref)
  }

  /// Stores the token for the next join and pushes it to every joined channel. `nil` asks the
  /// provider again, and keeps the current token when there is none: the server never receives
  /// a null token.
  package func setAuth(_ token: String?) async {
    guard let token else {
      if await refreshAccessToken() { withState { $0.pushAccessTokenToJoinedChannels() } }
      return
    }
    withState { state in
      let generation = state.tokens.beginRefresh()
      guard state.tokens.apply(token, generation: generation) else { return }
      state.scheduleTokenRefresh()
      state.pushAccessTokenToJoinedChannels()
    }
  }

  // MARK: - Presence API

  package func presenceState(_ topic: String) -> PresenceState {
    withState { $0.channels[topic]?.presence.state ?? PresenceState() }
  }

  /// Empty unless `owner` holds the topic's record.
  package func presence(_ topic: String, owner: ChannelOwner) -> PresenceState {
    withState { state in
      guard let record = state.channels[topic], record.owner === owner else {
        return PresenceState()
      }
      return record.presence.state
    }
  }

  /// Tracks `payload` on a subscribed channel, re-sent after every rejoin. Calls inside the
  /// rate window are coalesced to the newest payload; an unchanged payload is not resent.
  ///
  /// Returns once the server acknowledged the push, or at once when the push was coalesced or
  /// dropped as unchanged. On a channel joined without presence, it joins again with presence
  /// enabled and returns once that join succeeds; the rejoin sends the payload, so other clients
  /// see one join. A call while a rejoin of a tracking channel is in flight replaces the payload
  /// that join sends, and returns once it succeeds.
  package func trackPresence(_ topic: String, owner: ChannelOwner, payload: JSONObject)
    async throws
  {
    let ref = try await gate(topic) { state in
      // A join already in flight sends `trackedPayload` once it succeeds: replace it and wait.
      if let record = state.channels[topic], record.owner === owner,
        case .subscribing = record.state, record.presence.trackedPayload != nil
      {
        state.channels[topic]?.presence.trackedPayload = payload
        return .wait
      }
      _ = try state.joinRefForPush(topic, owner: owner)
      state.channels[topic]?.presence.trackedPayload = payload
      if state.channels[topic]?.config.presence.enabled == false {
        state.applyChannel(topic, .bindingsChanged)
        return .wait
      }
      guard
        let ref = try state.throttledSend(
          topic, event: "presence",
          payload: ["type": "presence", "event": "track", "payload": .object(payload)],
          keyPath: \.presencePush, window: state.configuration.presenceTrackInterval)
      else { return .done }
      state.expectReply(ref)
      return .ack(ref)
    }
    guard let ref else { return }
    do {
      _ = try await awaitAcknowledgement(ref: ref)
    } catch let error as RealtimeError
      where error.kind == .server || error.kind == .payloadTooLarge
    {
      // The server refused this payload; re-sending it on every rejoin would be refused too.
      withState { state in
        guard state.channels[topic]?.presence.trackedPayload == payload else { return }
        state.channels[topic]?.presence.trackedPayload = nil
        state.channels[topic]?.presencePush.lastSent = nil
      }
      throw error
    }
  }

  package func untrackPresence(_ topic: String, owner: ChannelOwner) async throws {
    let ref = try withState { state throws -> String? in
      _ = try state.joinRefForPush(topic, owner: owner)
      state.channels[topic]?.presence.trackedPayload = nil
      guard
        let ref = try state.throttledSend(
          topic, event: "presence", payload: ["type": "presence", "event": "untrack"],
          keyPath: \.presencePush, window: state.configuration.presenceTrackInterval)
      else { return nil }
      state.expectReply(ref)
      return ref
    }
    guard let ref else { return }
    _ = try await awaitAcknowledgement(ref: ref)
  }

  /// Joins again with presence enabled, unless the channel already joins with it. The server only
  /// sends `presence_state` to a join that enabled presence.
  package func enablePresence(_ topic: String, owner: ChannelOwner) {
    withState { state in
      guard let record = state.channels[topic], record.owner === owner,
        !record.config.presence.enabled
      else { return }
      state.channels[topic]?.config.presence.enabled = true
      state.applyChannel(topic, .bindingsChanged)
    }
  }

  // MARK: - Replies

  func awaitJoinReply(_ topic: String, ref: String) async {
    let extra = withState { $0.channels[topic]?.config.extraJoinTimeout } ?? .zero
    do {
      let reply = try await withTimeout(configuration.timeout + extra, clock: clock) {
        try await self.waitForReply(ref)
      }
      withState { state in
        guard state.channels[topic]?.joinRef == ref else { return }
        let result = state.joinResult(topic, reply: reply)
        state.applyChannel(topic, .joinReplied(result))
      }
    } catch is TimeoutError {
      withState { state in
        guard state.channels[topic]?.joinRef == ref else { return }
        state.applyChannel(topic, .joinTimedOut)
      }
    } catch {
      // The socket went away; `channelsSocketLost` already moved the channel on.
    }
  }

  private func awaitAcknowledgement(ref: String) async throws -> JSONObject {
    let reply: RealtimeMessageV2
    do {
      reply = try await withTimeout(configuration.timeout, clock: clock) {
        try await self.waitForReply(ref)
      }
    } catch is TimeoutError {
      throw RealtimeError(kind: .timeout, message: "no reply within \(configuration.timeout)")
    }
    if reply.status == .error {
      let response = reply.payload["response"]
      throw RealtimeError.ackError(
        reason: response?.stringValue ?? response?.objectValue?["reason"]?.stringValue ?? "")
    }
    return reply.payload
  }

  /// Resumes with the `phx_reply` for `ref`, with `.notConnected` when the socket goes away
  /// first, or with `CancellationError` when the waiting task is cancelled (which is how
  /// `withTimeout` unwinds it).
  private func waitForReply(_ ref: String) async throws -> RealtimeMessageV2 {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        withState { $0.awaitReply(ref, continuation) }
      }
    } onCancel: {
      withState { $0.cancelReply(ref) }
    }
  }

  /// Asks the provider for a token and keeps it if it is newer than any refresh that started
  /// later. Returns whether the stored token changed. Either way the next refresh is scheduled,
  /// so a provider that fails or returns the old token is asked again.
  @discardableResult
  func refreshAccessToken() async -> Bool {
    guard let provider = configuration.accessToken else { return false }
    let generation = withState { $0.tokens.beginRefresh() }
    let result = try? await provider()
    return withState { [configuration] state in
      let changed = state.tokens.apply(result, generation: generation)
      state.scheduleTokenRefresh(atLeast: configuration.accessTokenRetryInterval)
      return changed
    }
  }

  // MARK: - Supervisor

  func run(generation: Int) async {
    defer {
      withState { state in
        guard generation == state.generation else { return }
        if Task.isCancelled || state.isShutDown {
          state.cancel(state.tokenRefreshTimer?.task)
          state.applyConnection(.disconnectRequested)
        }
        if generation == state.generation { state.supervisor = nil }
      }
    }
    while true {
      let (signals, wake) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
      // Reading the state and registering the wake signal in one critical section means a wake
      // either finds the signal or has already moved the machine to `.connecting`.
      let step = withState { state -> SupervisorStep in
        guard !Task.isCancelled, !state.isShutDown, generation == state.generation else {
          return .stop
        }
        switch state.connection {
        case .connecting:
          return .attempt
        case .reconnecting(_, let retryIn, _):
          state.wakeSignal = wake
          return .sleep(retryIn)
        case .connected, .disconnected:
          return .stop
        }
      }
      switch step {
      case .attempt:
        await attemptConnection(generation: generation)
      case .stop:
        return
      case .sleep(let retryIn):
        let woke = await sleepUntilWoken(retryIn, signals: signals)
        withState { state in
          state.wakeSignal = nil
          guard generation == state.generation, !woke else { return }
          state.applyConnection(.retryTimerFired)
        }
        wake.finish()
      }
    }
  }

  private func attemptConnection(generation: Int) async {
    do {
      await refreshAccessToken()
      let connected = try await withTimeout(configuration.connectTimeout, clock: clock) {
        [transport, configuration] in
        try await transport.connect(to: configuration.url, headerFields: configuration.headers)
      }
      // One critical section, so `shutdown()` either sees the socket or makes this close it.
      let frames = withState { state -> AsyncStream<WebSocketFrame>? in
        guard generation == state.generation, !state.isShutDown else { return nil }
        state.socket = connected
        let (frames, continuation) = AsyncStream<WebSocketFrame>.makeStream(
          bufferingPolicy: .unbounded)
        state.outbound = continuation
        state.applyConnection(.upgradeSucceeded)
        return frames
      }
      guard let frames else {
        await connected.close(code: .normalClosure, reason: nil)
        return
      }
      await withTaskGroup(of: Void.self) { group in
        group.addTask { await self.readLoop(connected, generation: generation) }
        group.addTask { await self.writeLoop(connected, frames: frames) }
        group.addTask { await self.heartbeatLoop(generation: generation) }
        _ = await group.next()
        group.cancelAll()
        for await _ in group {}
      }
    } catch is CancellationError {
      return
    } catch is TimeoutError {
      withState {
        $0.applyConnection(
          .upgradeFailed(RealtimeError(kind: .timeout, message: "connect timed out")))
      }
    } catch let error as RealtimeError {
      withState { $0.applyConnection(.upgradeFailed(error)) }
    } catch {
      withState {
        $0.applyConnection(.upgradeFailed(.transport("\(error)", underlyingError: error)))
      }
    }
  }

  /// Sleeps `duration` on the clock, or returns early with `true` on a wake signal.
  private func sleepUntilWoken(_ duration: Duration, signals: AsyncStream<Void>) async -> Bool {
    return await withTaskGroup(of: Bool.self) { group in
      group.addTask { [clock] in
        try? await clock.sleep(for: duration)
        return false
      }
      group.addTask {
        var iterator = signals.makeAsyncIterator()
        return await iterator.next() != nil
      }
      let woke = await group.next() ?? false
      group.cancelAll()
      return woke
    }
  }

  private func readLoop(_ connected: any WebSocketConnection, generation: Int) async {
    for await event in connected.events {
      switch event {
      case .frame(.text(let text)):
        let message: RealtimeMessageV2?
        do {
          message = try serializer.decodeText(text)
        } catch {
          logger.warning("dropping undecodable frame: \(error)")
          message = nil
        }
        let isCurrent = withState { state in
          guard generation == state.generation else { return false }
          if let message { state.handle(message) }
          return true
        }
        guard isCurrent else { return }
      case .frame(.binary(let data)):
        let broadcast: DecodedBroadcast?
        do {
          broadcast = try serializer.decodeBinary(data)
        } catch {
          logger.warning("dropping undecodable binary frame: \(error)")
          broadcast = nil
        }
        let isCurrent = withState { state in
          guard generation == state.generation else { return false }
          if let broadcast { state.yield(.broadcast(broadcast), to: broadcast.topic) }
          return true
        }
        guard isCurrent else { return }
      case .closed(let code, let reason):
        withState { state in
          guard generation == state.generation else { return }
          state.socketWentAway()
          state.applyConnection(.transportClosed(code: code, reason: reason))
        }
        return
      }
    }
    withState { state in
      guard generation == state.generation else { return }
      state.socketWentAway()
      state.applyConnection(.transportClosed(code: nil, reason: nil))
    }
  }

  private func writeLoop(_ connected: any WebSocketConnection, frames: AsyncStream<WebSocketFrame>)
    async
  {
    for await frame in frames {
      do {
        try await connected.send(frame)
      } catch {
        logger.warning("send failed: \(error)")
        await connected.close(code: .goingAway, reason: nil)
        return
      }
    }
  }

  private func heartbeatLoop(generation: Int) async {
    while !Task.isCancelled {
      guard (try? await clock.sleep(for: configuration.heartbeatInterval)) != nil else { return }
      let ref = withState { state -> String? in
        guard generation == state.generation, state.connection.isConnected else { return nil }
        let ref = state.makeRef()
        let heartbeat = RealtimeMessageV2(
          joinRef: nil, ref: ref, topic: "phoenix", event: "heartbeat", payload: [:])
        guard (try? state.enqueue(.text(try state.serializer.encodeText(heartbeat)))) != nil
        else { return nil }
        state.expectReply(ref)
        state.yieldHeartbeat(.sent)
        return ref
      }
      guard let ref else { return }
      do {
        let latency = try await clock.measure {
          _ = try await withTimeout(configuration.heartbeatTimeout, clock: clock) {
            try await self.waitForReply(ref)
          }
        }
        withState { $0.yieldHeartbeat(.acknowledged(latency: latency)) }
      } catch is TimeoutError {
        withState { state in
          guard generation == state.generation else { return }
          state.yieldHeartbeat(.timedOut)
          state.applyConnection(.heartbeatTimedOut)
        }
        return
      } catch {
        return
      }
    }
  }
}
