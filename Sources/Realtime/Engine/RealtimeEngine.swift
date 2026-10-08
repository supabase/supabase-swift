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

/// The one mutable core of Realtime: one socket, one supervisor task, pure machines for the
/// connection and every channel, and fan-out to listeners.
package actor RealtimeEngine {
  private enum ReplySlot {
    case expected
    case waiting(CheckedContinuation<RealtimeMessageV2, any Error>)
    case arrived(RealtimeMessageV2)
  }

  private struct ChannelRecord {
    let owner: ChannelOwner
    var config: RealtimeJoinConfig
    var state: ChannelMachine.State = .unsubscribed
    var joinRef: String?
    var subscribeWaiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
    var pendingLeaveRef: String?
    /// Leaves that found another leave in flight, resumed once the channel stops unsubscribing.
    var leaveWaiters: [CheckedContinuation<Void, Never>] = []
    var joinTask: Task<Void, Never>?
    var rejoinTask: Task<Void, Never>?
    var lingerTask: Task<Void, Never>?
    var presence = PresenceTracker()
    var tokenPush = Throttle()
    var presencePush = Throttle()
  }

  /// One send per window per channel; a newer value inside the window replaces the pending one.
  private struct Throttle {
    var window: Task<Void, Never>?
    var pending: JSONObject?
    var lastSent: JSONObject?
  }

  private struct ListenerRegistry {
    var channelStates: [String: [UUID: AsyncStream<ChannelMachine.State>.Continuation]] = [:]
    var connectionStates: [UUID: AsyncStream<ConnectionMachine.State>.Continuation] = [:]
  }

  private let configuration: RealtimeEngineConfiguration
  private let transport: any WebSocketTransport
  let clock: any Clock<Duration>
  private let serializer = RealtimeSerializer()
  let logger: Logger
  /// What public handles read without awaiting the actor.
  package nonisolated let mirror = EngineMirror()
  private var registry = ListenerRegistry()

  /// What ``shutdown()`` reaches without awaiting the actor.
  private struct Handles {
    var supervisor: Task<Void, Never>?
    var socket: (any WebSocketConnection)?
    var isShutDown = false
  }

  private nonisolated let handles = LockIsolated(Handles())

  private var connection: ConnectionMachine.State = .disconnected(nil)
  private var channels: [String: ChannelRecord] = [:]
  private var supervisor: Task<Void, Never>? {
    get { handles.supervisor }
    set { handles.withValue { $0.supervisor = newValue } }
  }
  /// Bumped on every supervisor start and every forced teardown, so callbacks from an older
  /// socket are ignored.
  private var generation = 0
  private var socket: (any WebSocketConnection)? { handles.socket }
  private var outbound: AsyncStream<WebSocketFrame>.Continuation?
  private var wakeSignal: AsyncStream<Void>.Continuation?
  private var idleTask: Task<Void, Never>?
  /// One slot per ref a caller will wait on. A reply for a ref with no slot is dropped: either it
  /// is late (the waiter timed out) or nobody awaits it (a push sent without a reply, a leave the
  /// machine sent on its own).
  private var pendingReplies: [String: ReplySlot] = [:]
  private var connectWaiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
  /// `addChannel` calls waiting for a retired owner's record to go, by topic.
  private var removalWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

  var pendingReplyCount: Int { pendingReplies.count }
  private var refCounter = 0
  private var tokens = TokenState()
  private var tokenRefreshTask: Task<Void, Never>?

  package init(
    configuration: RealtimeEngineConfiguration,
    transport: any WebSocketTransport,
    clock: any Clock<Duration> = ContinuousClock()
  ) {
    self.configuration = configuration
    self.transport = transport
    self.clock = clock
    self.logger = configuration.logger
    _ = tokens.apply(configuration.initialAccessToken, generation: tokens.beginRefresh())
  }

  // MARK: - Connection API

  package var connectionState: ConnectionMachine.State { connection }

  /// Returns once the socket is connected. Throws the fatal error when the upgrade is refused
  /// for good (401, 403, 404), `.notConnected` when `disconnect()` wins the race, and
  /// `CancellationError` when the calling task is cancelled; the socket keeps connecting.
  package func connect() async throws {
    switch connection {
    case .connected: return
    case .disconnected, .reconnecting: applyConnection(.connectRequested)
    case .connecting: break
    }
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
        } else {
          connectWaiters[id] = continuation
        }
      }
    } onCancel: {
      Task { await self.cancelConnectWaiter(id) }
    }
  }

  private func cancelConnectWaiter(_ id: UUID) {
    connectWaiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
  }

  /// Leaves every channel, closes the socket, and returns once it is closed.
  package func disconnect() async {
    applyConnection(.disconnectRequested)
    await supervisor?.value
  }

  /// Closes the socket but keeps every channel wanting its subscription.
  package func pause() async {
    applyConnection(.pauseRequested)
    await supervisor?.value
  }

  /// Reconnects after `pause()` and rejoins every channel that was subscribed.
  package func resume() async {
    if case .disconnected = connection { applyConnection(.resumeRequested) }
    try? await connect()
  }

  /// The network path became satisfied or the app came to the foreground.
  package func wake() {
    applyConnection(.wakeSignal)
  }

  /// Stops the engine for good without waiting: finishes every stream, cancels the supervisor and
  /// closes the socket.
  /// The supervisor then moves the engine to `.disconnected`, and a later connect ends there
  /// at once. For a `deinit`, which cannot await.
  package nonisolated func shutdown() {
    let (supervisor, socket) = handles.withValue {
      $0.isShutDown = true
      return ($0.supervisor, $0.socket)
    }
    mirror.shutDown()
    supervisor?.cancel()
    if let socket {
      Task { await socket.close(code: .normalClosure, reason: nil) }
    }
  }

  /// The token joins carry: the last one `setAuth(_:)` or the provider gave.
  package var accessToken: String? { tokens.token }

  package func connectionStates() -> AsyncStream<ConnectionMachine.State> {
    let (stream, continuation) = AsyncStream<ConnectionMachine.State>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    let id = UUID()
    continuation.onTermination = { [weak self] _ in
      Task { await self?.forgetListener { $0.connectionStates[id] = nil } }
    }
    registry.connectionStates[id] = continuation
    return stream
  }

  /// Every heartbeat step, unbounded so a latency display misses none. Registers before it
  /// returns.
  package nonisolated func heartbeats() -> AsyncStream<HeartbeatEvent> {
    mirror.heartbeats()
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
    while let record = channels[topic], record.owner !== owner, record.owner.isRetired,
      !owner.isRetired
    {
      await withCheckedContinuation { removalWaiters[topic, default: []].append($0) }
    }
    guard !owner.isRetired else { return }
    if let record = channels[topic] {
      if record.owner === owner { channels[topic]?.config = config }
      return
    }
    channels[topic] = ChannelRecord(owner: owner, config: config)
    mirror.install(topic, owner: owner.id)
    applyConnection(.channelAdded)
  }

  private func isOwner(_ owner: ChannelOwner, of topic: String) -> Bool {
    channels[topic]?.owner === owner
  }

  /// Replaces the channel's postgres bindings. A joined or joining channel joins again with them.
  ///
  /// A channel only adds bindings, and each addition sends its snapshot from its own task, so a
  /// list no longer than the current one is unchanged or stale and is ignored.
  package func updateBindings(
    _ topic: String, owner: ChannelOwner, _ bindings: [PostgresJoinConfig]
  ) {
    guard let record = channels[topic], record.owner === owner,
      bindings.count > record.config.postgresChanges.count
    else { return }
    channels[topic]?.config.postgresChanges = bindings
    applyChannel(topic, .bindingsChanged)
  }

  /// Leaves and forgets the owner's channel, and finishes every stream of `owner`.
  package func removeChannel(_ topic: String, owner: ChannelOwner) async {
    guard isOwner(owner, of: topic) else {
      mirror.removeChannel(topic, owner: owner.id)
      return
    }
    await leave(topic)
    defer { removalWaiters.removeValue(forKey: topic)?.forEach { $0.resume() } }
    guard isOwner(owner, of: topic) else { return }
    channels[topic]?.rejoinTask?.cancel()
    channels[topic]?.joinTask?.cancel()
    channels[topic]?.lingerTask?.cancel()
    resetThrottles(topic)
    rejectSubscribe(
      topic, with: RealtimeError(kind: .notSubscribed, message: "channel \(topic) was removed"))
    channels[topic]?.leaveWaiters.forEach { $0.resume() }
    channels[topic] = nil
    mirror.removeChannel(topic, owner: owner.id)
    registry.channelStates[topic]?.values.forEach { $0.finish() }
    registry.channelStates[topic] = nil
    if channels.isEmpty { applyConnection(.lastChannelRemoved) }
  }

  package func channelState(_ topic: String) -> ChannelMachine.State? {
    channels[topic]?.state
  }

  /// The server ids of the channel's postgres bindings, by position, from the last join.
  package func postgresChangeIDs(_ topic: String) -> [Int] {
    mirror.postgresChangeIDs(topic)
  }

  /// Returns once the join is acknowledged. Throws the server's reason for a fatal join error,
  /// `.notSubscribed` when the channel is unsubscribed before the join completes, and
  /// `CancellationError` when the calling task is cancelled; the channel keeps joining.
  package func subscribe(_ topic: String, owner: ChannelOwner) async throws {
    guard isOwner(owner, of: topic) else {
      throw RealtimeError(
        kind: .notSubscribed,
        message: owner.isRetired
          ? "channel \(topic) was removed" : "unknown channel \(topic)")
    }
    applyChannel(topic, .subscribeRequested)
    if channels[topic]?.state.isSubscribed == true { return }
    try await waitForSubscription(topic)
  }

  /// Resumes on the channel's next `resolveSubscribe` or `rejectSubscribe`.
  private func waitForSubscription(_ topic: String) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
        } else if channels[topic] == nil {
          continuation.resume(
            throwing: RealtimeError(kind: .notSubscribed, message: "channel \(topic) was removed"))
        } else {
          channels[topic]?.subscribeWaiters[id] = continuation
        }
      }
    } onCancel: {
      Task { await self.cancelSubscribeWaiter(topic, id: id) }
    }
  }

  private func cancelSubscribeWaiter(_ topic: String, id: UUID) {
    channels[topic]?.subscribeWaiters.removeValue(forKey: id)?.resume(
      throwing: CancellationError())
  }

  /// Sends the leave and returns once the server replied, the reply timed out, or the socket
  /// was already gone.
  package func unsubscribe(_ topic: String, owner: ChannelOwner) async {
    guard isOwner(owner, of: topic) else { return }
    await leave(topic)
  }

  private func leave(_ topic: String) async {
    if case .unsubscribing = channels[topic]?.state {
      await withCheckedContinuation { channels[topic]?.leaveWaiters.append($0) }
      return
    }
    applyChannel(topic, .unsubscribeRequested)
    guard case .unsubscribing = channels[topic]?.state else { return }
    if let ref = channels[topic]?.pendingLeaveRef {
      expectReply(ref)
      _ = try? await withTimeout(configuration.timeout, clock: clock) {
        try await self.waitForReply(ref)
      }
    }
    applyChannel(topic, .leaveCompleted)
  }

  package func channelStates(_ topic: String) -> AsyncStream<ChannelMachine.State> {
    let (stream, continuation) = AsyncStream<ChannelMachine.State>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    let id = UUID()
    continuation.onTermination = { [weak self] _ in
      Task { await self?.forgetListener { $0.channelStates[topic]?[id] = nil } }
    }
    registry.channelStates[topic, default: [:]][id] = continuation
    return stream
  }

  /// Every message `owner` receives on the topic, unbounded. Registers before it returns; ending
  /// the iteration removes the listener.
  package nonisolated func inbound(_ topic: String, owner: ChannelOwner) -> AsyncStream<
    ChannelInbound
  > {
    mirror.inbound(topic, owner: owner)
  }

  package nonisolated func listenerCount(_ topic: String) -> Int {
    mirror.listenerCount(topic)
  }

  private func forgetListener(_ remove: @Sendable (inout ListenerRegistry) -> Void) {
    remove(&registry)
  }

  /// Sends a push on a subscribed channel. With `awaitReply` it returns the reply payload, or
  /// throws `.timeout`, `.notConnected` when the socket goes away first, or the server's ack
  /// error.
  @discardableResult
  package func send(
    _ topic: String, owner: ChannelOwner, event: String, payload: JSONObject, awaitReply: Bool
  ) async throws -> JSONObject? {
    let joinRef = try joinRefForPush(topic, owner: owner)
    let ref = makeRef()
    let message = RealtimeMessageV2(
      joinRef: joinRef, ref: ref, topic: topic, event: event, payload: payload)
    try enqueue(.text(try serializer.encodeText(message)))
    guard awaitReply else { return nil }
    expectReply(ref)
    return try await awaitAcknowledgement(ref: ref)
  }

  /// Sends a kind-3 binary broadcast on a subscribed channel.
  package func sendBroadcast(
    _ topic: String, owner: ChannelOwner, event: String, data: Data, awaitReply: Bool = false
  ) async throws {
    let joinRef = try joinRefForPush(topic, owner: owner)
    let ref = makeRef()
    let frame = try serializer.encodeBroadcastPush(
      joinRef: joinRef, ref: ref, topic: topic, event: event, binaryPayload: data)
    try enqueue(.binary(frame))
    guard awaitReply else { return }
    expectReply(ref)
    _ = try await awaitAcknowledgement(ref: ref)
  }

  /// Stores the token for the next join and pushes it to every joined channel. `nil` asks the
  /// provider again, and keeps the current token when there is none: the server never receives
  /// a null token.
  package func setAuth(_ token: String?) async {
    guard let token else {
      if await refreshAccessToken() { pushAccessTokenToJoinedChannels() }
      return
    }
    guard tokens.apply(token, generation: tokens.beginRefresh()) else { return }
    scheduleTokenRefresh()
    pushAccessTokenToJoinedChannels()
  }

  // MARK: - Presence API

  package func presenceState(_ topic: String) -> PresenceState {
    channels[topic]?.presence.state ?? PresenceState()
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
    // A join already in flight sends `trackedPayload` once it succeeds: replace it and wait.
    if let record = channels[topic], record.owner === owner, case .subscribing = record.state,
      record.presence.trackedPayload != nil
    {
      channels[topic]?.presence.trackedPayload = payload
      try await waitForSubscription(topic)
      return
    }
    _ = try joinRefForPush(topic, owner: owner)
    channels[topic]?.presence.trackedPayload = payload
    if channels[topic]?.config.presence.enabled == false {
      applyChannel(topic, .bindingsChanged)
      try await waitForSubscription(topic)
      return
    }
    do {
      try await sendPresence(
        topic, payload: ["type": "presence", "event": "track", "payload": .object(payload)])
    } catch let error as RealtimeError
      where error.kind == .server || error.kind == .payloadTooLarge
    {
      // The server refused this payload; re-sending it on every rejoin would be refused too.
      if channels[topic]?.presence.trackedPayload == payload {
        channels[topic]?.presence.trackedPayload = nil
        channels[topic]?.presencePush.lastSent = nil
      }
      throw error
    }
  }

  package func untrackPresence(_ topic: String, owner: ChannelOwner) async throws {
    _ = try joinRefForPush(topic, owner: owner)
    channels[topic]?.presence.trackedPayload = nil
    try await sendPresence(topic, payload: ["type": "presence", "event": "untrack"])
  }

  private func sendPresence(_ topic: String, payload: JSONObject) async throws {
    guard
      let ref = try throttledSend(
        topic, event: "presence", payload: payload, keyPath: \.presencePush,
        window: configuration.presenceTrackInterval)
    else { return }
    expectReply(ref)
    _ = try await awaitAcknowledgement(ref: ref)
  }

  /// Joins again with presence enabled, unless the channel already joins with it. The server only
  /// sends `presence_state` to a join that enabled presence.
  package func enablePresence(_ topic: String, owner: ChannelOwner) {
    guard let record = channels[topic], record.owner === owner, !record.config.presence.enabled
    else { return }
    channels[topic]?.config.presence.enabled = true
    applyChannel(topic, .bindingsChanged)
  }

  private func pushAccessTokenToJoinedChannels() {
    guard let token = tokens.token, connection.isConnected else { return }
    for (topic, record) in channels where record.state.isSubscribed {
      _ = try? throttledSend(
        topic, event: "access_token", payload: ["access_token": .string(token)],
        keyPath: \.tokenPush, window: configuration.accessTokenPushInterval)
    }
  }

  /// Sends now if the channel's window is open, otherwise keeps `payload` as the one to send
  /// when the window closes. An unchanged payload is dropped, as the server would drop it.
  ///
  /// Returns the ref of the push when it went out now, and `nil` when it was kept or dropped.
  private func throttledSend(
    _ topic: String, event: String, payload: JSONObject,
    keyPath: WritableKeyPath<ChannelRecord, Throttle>, window: Duration
  ) throws -> String? {
    guard var record = channels[topic], record.state.isSubscribed, let joinRef = record.joinRef
    else { return nil }
    if record[keyPath: keyPath].window != nil {
      record[keyPath: keyPath].pending = payload
      channels[topic] = record
      return nil
    }
    guard record[keyPath: keyPath].lastSent != payload else { return nil }
    let ref = makeRef()
    let message = RealtimeMessageV2(
      joinRef: joinRef, ref: ref, topic: topic, event: event, payload: payload)
    try enqueue(.text(try serializer.encodeText(message)))
    record[keyPath: keyPath].lastSent = payload
    record[keyPath: keyPath].pending = nil
    record[keyPath: keyPath].window = Task {
      try? await clock.sleep(for: window)
      guard !Task.isCancelled else { return }
      closeThrottleWindow(topic, event: event, keyPath: keyPath, window: window)
    }
    channels[topic] = record
    return ref
  }

  private func closeThrottleWindow(
    _ topic: String, event: String, keyPath: WritableKeyPath<ChannelRecord, Throttle>,
    window: Duration
  ) {
    guard var record = channels[topic] else { return }
    record[keyPath: keyPath].window = nil
    let pending = record[keyPath: keyPath].pending
    record[keyPath: keyPath].pending = nil
    channels[topic] = record
    if let pending {
      _ = try? throttledSend(
        topic, event: event, payload: pending, keyPath: keyPath, window: window)
    }
  }

  private func resetThrottles(_ topic: String) {
    channels[topic]?.tokenPush.window?.cancel()
    channels[topic]?.presencePush.window?.cancel()
    channels[topic]?.tokenPush = Throttle()
    channels[topic]?.presencePush = Throttle()
  }

  // MARK: - Machines

  private func applyConnection(_ event: ConnectionMachine.Event) {
    let before = connection.key
    let effects = ConnectionMachine.transition(
      &connection, event, configuration: configuration.connection)
    for effect in effects { perform(effect) }
    if connection.key != before {
      let state = connection
      mirror.setConnection(state.publicStatus)
      registry.connectionStates.values.forEach { $0.yield(state) }
    }
    resolveConnectWaiters()
  }

  private func resolveConnectWaiters() {
    guard !connectWaiters.isEmpty else { return }
    switch connection {
    case .connected:
      let waiters = connectWaiters.values
      connectWaiters = [:]
      waiters.forEach { $0.resume() }
    case .disconnected(let error):
      let waiters = connectWaiters.values
      connectWaiters = [:]
      let failure = error ?? RealtimeError(kind: .notConnected, message: "disconnected")
      waiters.forEach { $0.resume(throwing: failure) }
    case .connecting, .reconnecting:
      break
    }
  }

  private func perform(_ effect: ConnectionMachine.Effect) {
    switch effect {
    case .openTransport:
      if supervisor == nil {
        generation += 1
        let generation = generation
        supervisor = Task { await self.run(generation: generation) }
      } else {
        wakeSignal?.yield()
      }
    case .closeTransport(let code):
      if let socket {
        Task { await socket.close(code: code, reason: nil) }
      } else {
        supervisor?.cancel()
        supervisor = nil
        generation += 1
      }
    case .startHeartbeat, .stopHeartbeat, .scheduleRetry:
      break
    case .cancelRetry:
      wakeSignal?.yield()
    case .scheduleIdleDisconnect(let delay):
      idleTask?.cancel()
      idleTask = Task {
        try? await clock.sleep(for: delay)
        guard !Task.isCancelled else { return }
        applyConnection(.idleTimerFired)
      }
    case .cancelIdleDisconnect:
      idleTask?.cancel()
      idleTask = nil
    case .rejoinAllChannels:
      for topic in channels.keys { applyChannel(topic, .socketConnected) }
    case .failPendingReplies:
      failPendingReplies()
    case .channelsSocketLost:
      let error = connection.error ?? RealtimeError.socketClosed(code: nil, reason: nil)
      for topic in channels.keys {
        applyChannel(topic, .socketLost(error))
        if !error.isRetryable { rejectSubscribe(topic, with: error) }
      }
    case .channelsUnsubscribed:
      for topic in channels.keys {
        applyChannel(topic, .unsubscribeRequested)
        applyChannel(topic, .leaveCompleted)
      }
    }
  }

  private func applyChannel(_ topic: String, _ event: ChannelMachine.Event) {
    guard var record = channels[topic] else { return }
    let before = record.state.key
    let effects = ChannelMachine.transition(
      &record.state, event, configuration: configuration.channel)
    channels[topic] = record
    for effect in effects { perform(effect, on: topic) }
    if let state = channels[topic]?.state, state.key != before {
      mirror.setChannel(topic, state.publicStatus)
      registry.channelStates[topic]?.values.forEach { $0.yield(state) }
      if before == "unsubscribing" {
        let waiters = channels[topic]?.leaveWaiters ?? []
        channels[topic]?.leaveWaiters = []
        waiters.forEach { $0.resume() }
      }
    }
  }

  private func perform(_ effect: ChannelMachine.Effect, on topic: String) {
    switch effect {
    case .sendJoin:
      sendJoin(topic)
    case .sendLeave:
      sendLeave(topic)
    case .scheduleRejoin(let delay):
      channels[topic]?.rejoinTask?.cancel()
      channels[topic]?.rejoinTask = Task {
        try? await clock.sleep(for: delay)
        guard !Task.isCancelled else { return }
        applyChannel(topic, .rejoinTimerFired)
      }
    case .cancelRejoin:
      channels[topic]?.rejoinTask?.cancel()
      channels[topic]?.rejoinTask = nil
    case .refreshToken:
      Task {
        await refreshAccessToken()
        applyChannel(topic, .tokenRefreshed)
      }
    case .emitResubscribed:
      mirror.yield(.resubscribed, to: topic)
    case .resolveSubscribe:
      let waiters = channels[topic]?.subscribeWaiters.values.map { $0 } ?? []
      channels[topic]?.subscribeWaiters = [:]
      waiters.forEach { $0.resume() }
    case .rejectSubscribe:
      let error =
        channels[topic]?.state.error
        ?? RealtimeError(kind: .notSubscribed, message: "channel \(topic) was unsubscribed")
      rejectSubscribe(topic, with: error)
    case .resendPresenceTrack:
      if let payload = channels[topic]?.presence.trackedPayload {
        _ = try? throttledSend(
          topic, event: "presence",
          payload: ["type": "presence", "event": "track", "payload": .object(payload)],
          keyPath: \.presencePush, window: configuration.presenceTrackInterval)
      }
    case .finishDataStreams:
      mirror.finishInbound(topic)
    case .scheduleLinger(let delay):
      channels[topic]?.lingerTask?.cancel()
      channels[topic]?.lingerTask = Task {
        try? await clock.sleep(for: delay)
        guard !Task.isCancelled else { return }
        applyChannel(topic, .lingerTimerFired)
      }
    case .cancelLinger:
      channels[topic]?.lingerTask?.cancel()
      channels[topic]?.lingerTask = nil
    }
  }

  private func rejectSubscribe(_ topic: String, with error: RealtimeError) {
    let waiters = channels[topic]?.subscribeWaiters.values.map { $0 } ?? []
    channels[topic]?.subscribeWaiters = [:]
    waiters.forEach { $0.resume(throwing: error) }
  }

  // MARK: - Join and leave

  private func sendJoin(_ topic: String) {
    guard connection.isConnected, outbound != nil else {
      if configuration.connectOnSubscribe, case .disconnected = connection {
        applyConnection(.connectRequested)
      }
      return
    }
    resetThrottles(topic)
    guard var record = channels[topic] else { return }
    let ref = makeRef()
    record.config.presence.enabled =
      record.config.presence.enabled || record.presence.trackedPayload != nil
    record.presence.reset()
    channels[topic] = record
    mirror.setPresence(topic, record.presence.state)
    let payload = RealtimeJoinPayload(
      config: record.config, accessToken: tokens.token,
      version: configuration.headers[.xClientInfo])
    guard let encoded = try? JSONObject(payload) else {
      logger.error("failed to encode the phx_join payload for \(topic)")
      return
    }
    let message = RealtimeMessageV2(
      joinRef: ref, ref: ref, topic: topic, event: "phx_join", payload: encoded)
    channels[topic]?.joinRef = ref
    channels[topic]?.joinTask?.cancel()
    do {
      try enqueue(.text(try serializer.encodeText(message)))
    } catch {
      logger.error("failed to send phx_join for \(topic): \(error)")
      return
    }
    expectReply(ref)
    channels[topic]?.joinTask = Task { await self.awaitJoinReply(topic, ref: ref) }
  }

  private func awaitJoinReply(_ topic: String, ref: String) async {
    do {
      let timeout = configuration.timeout + (channels[topic]?.config.extraJoinTimeout ?? .zero)
      let reply = try await withTimeout(timeout, clock: clock) {
        try await self.waitForReply(ref)
      }
      guard channels[topic]?.joinRef == ref else { return }
      applyChannel(topic, .joinReplied(joinResult(topic, reply: reply)))
    } catch is TimeoutError {
      guard channels[topic]?.joinRef == ref else { return }
      applyChannel(topic, .joinTimedOut)
    } catch {
      // The socket went away; `channelsSocketLost` already moved the channel on.
    }
  }

  private func joinResult(_ topic: String, reply: RealtimeMessageV2)
    -> Result<ChannelMachine.JoinReply, RealtimeError>
  {
    let response = reply.payload["response"]?.objectValue ?? [:]
    guard reply.status == .ok else {
      let reason = response["reason"]?.stringValue ?? "Unknown Error on Channel"
      return .failure(.joinError(reason: reason))
    }
    let declared = channels[topic]?.config.postgresChanges ?? []
    let replied =
      (try? JSONDecoder().decode(
        [PostgresJoinConfig].self,
        from: JSONEncoder().encode(response["postgres_changes"] ?? .array([])))) ?? []
    return ChannelMachine.verify(declared: declared, replied: replied).map { ids in
      mirror.setPostgresChangeIDs(topic, ids)
      return ChannelMachine.JoinReply(postgresChangeIDs: ids)
    }
  }

  private func sendLeave(_ topic: String) {
    guard connection.isConnected, let joinRef = channels[topic]?.joinRef else {
      applyChannel(topic, .leaveCompleted)
      return
    }
    let ref = makeRef()
    let message = RealtimeMessageV2(
      joinRef: joinRef, ref: ref, topic: topic, event: "phx_leave", payload: [:])
    channels[topic]?.pendingLeaveRef = ref
    try? enqueue(.text(try serializer.encodeText(message)))
  }

  /// Throws `.notSubscribed` unless `owner` holds the topic's record and it is joined.
  private func joinRefForPush(_ topic: String, owner: ChannelOwner) throws -> String {
    guard let record = channels[topic], record.owner === owner, record.state.isSubscribed,
      let joinRef = record.joinRef
    else {
      throw RealtimeError(
        kind: .notSubscribed, message: "channel \(topic) is not subscribed", isRetryable: false)
    }
    guard connection.isConnected else {
      throw RealtimeError(kind: .notConnected, message: "socket is not connected")
    }
    return joinRef
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

  // MARK: - Wire

  private func makeRef() -> String {
    refCounter += 1
    return String(refCounter)
  }

  private func enqueue(_ frame: WebSocketFrame) throws {
    guard let outbound else {
      throw RealtimeError(kind: .notConnected, message: "socket is not connected")
    }
    outbound.yield(frame)
  }

  /// Resumes with the `phx_reply` for `ref`, with `.notConnected` when the socket goes away
  /// first, or with `CancellationError` when the waiting task is cancelled (which is how
  /// `withTimeout` unwinds it).
  private func waitForReply(_ ref: String) async throws -> RealtimeMessageV2 {
    if case .arrived(let message)? = pendingReplies[ref] {
      pendingReplies[ref] = nil
      return message
    }
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
        } else {
          pendingReplies[ref] = .waiting(continuation)
        }
      }
    } onCancel: {
      Task { await self.cancelReply(ref) }
    }
  }

  /// Call in the same synchronous stretch as the `enqueue` so the reply cannot land before it.
  private func expectReply(_ ref: String) {
    if case .waiting? = pendingReplies[ref] { return }
    pendingReplies[ref] = .expected
  }

  private func cancelReply(_ ref: String) {
    if case .waiting(let waiter)? = pendingReplies.removeValue(forKey: ref) {
      waiter.resume(throwing: CancellationError())
    }
  }

  private func deliverReply(_ message: RealtimeMessageV2, ref: String) {
    switch pendingReplies[ref] {
    case .waiting(let waiter)?:
      pendingReplies[ref] = nil
      waiter.resume(returning: message)
    case .expected?:
      pendingReplies[ref] = .arrived(message)
    case .arrived?, nil:
      break
    }
  }

  private func failPendingReplies() {
    let slots = pendingReplies.values
    pendingReplies = [:]
    let error = RealtimeError(kind: .notConnected, message: "socket closed before the reply")
    for case .waiting(let waiter) in slots { waiter.resume(throwing: error) }
  }

  /// Asks the provider for a token and keeps it if it is newer than any refresh that started
  /// later. Returns whether the stored token changed. Either way the next refresh is scheduled,
  /// so a provider that fails or returns the old token is asked again.
  @discardableResult
  private func refreshAccessToken() async -> Bool {
    guard let provider = configuration.accessToken else { return false }
    let generation = tokens.beginRefresh()
    let result = try? await provider()
    let changed = tokens.apply(result, generation: generation)
    scheduleTokenRefresh(atLeast: configuration.accessTokenRetryInterval)
    return changed
  }

  /// Refreshes `accessTokenRefreshLeeway` before the token's `exp`, since the server closes
  /// every channel the moment it expires.
  private func scheduleTokenRefresh(atLeast minimum: Duration = .zero) {
    tokenRefreshTask?.cancel()
    tokenRefreshTask = nil
    guard
      let due = tokens.refreshDelay(now: Date(), leeway: configuration.accessTokenRefreshLeeway)
    else { return }
    let delay = max(due, minimum)
    tokenRefreshTask = Task {
      try? await clock.sleep(for: delay)
      guard !Task.isCancelled else { return }
      if await refreshAccessToken() { pushAccessTokenToJoinedChannels() }
    }
  }

  // MARK: - Supervisor

  private func run(generation: Int) async {
    defer {
      if generation == self.generation, Task.isCancelled || handles.isShutDown {
        tokenRefreshTask?.cancel()
        applyConnection(.disconnectRequested)
      }
      if generation == self.generation { supervisor = nil }
    }
    while !Task.isCancelled, !handles.isShutDown, generation == self.generation {
      guard case .connecting = connection else { return }
      await attemptConnection(generation: generation)
      guard generation == self.generation, case .reconnecting(_, let retryIn, _) = connection
      else { return }
      let woke = await sleepUntilWoken(retryIn)
      guard generation == self.generation else { return }
      if !woke { applyConnection(.retryTimerFired) }
    }
  }

  private func attemptConnection(generation: Int) async {
    do {
      await refreshAccessToken()
      let connected = try await withTimeout(configuration.connectTimeout, clock: clock) {
        [transport, configuration] in
        try await transport.connect(to: configuration.url, headerFields: configuration.headers)
      }
      // Checked and stored under one lock, so `shutdown()` either sees the socket or makes this
      // close it.
      let isCurrent =
        generation == self.generation
        && handles.withValue {
          guard !$0.isShutDown else { return false }
          $0.socket = connected
          return true
        }
      guard isCurrent else {
        await connected.close(code: .normalClosure, reason: nil)
        return
      }
      let (frames, continuation) = AsyncStream<WebSocketFrame>.makeStream(
        bufferingPolicy: .unbounded)
      outbound = continuation
      applyConnection(.upgradeSucceeded)
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
      applyConnection(.upgradeFailed(RealtimeError(kind: .timeout, message: "connect timed out")))
    } catch let error as RealtimeError {
      applyConnection(.upgradeFailed(error))
    } catch {
      applyConnection(.upgradeFailed(.transport("\(error)", underlyingError: error)))
    }
  }

  /// Sleeps `duration` on the clock, or returns early with `true` on a wake signal.
  private func sleepUntilWoken(_ duration: Duration) async -> Bool {
    let (signals, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    wakeSignal = continuation
    defer {
      wakeSignal = nil
      continuation.finish()
    }
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
      guard generation == self.generation else { return }
      switch event {
      case .frame(.text(let text)):
        handleText(text)
      case .frame(.binary(let data)):
        handleBinary(data)
      case .closed(let code, let reason):
        socketWentAway()
        applyConnection(.transportClosed(code: code, reason: reason))
        return
      }
    }
    guard generation == self.generation else { return }
    socketWentAway()
    applyConnection(.transportClosed(code: nil, reason: nil))
  }

  private func socketWentAway() {
    handles.withValue { $0.socket = nil }
    outbound?.finish()
    outbound = nil
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
      guard generation == self.generation, connection.isConnected else { return }
      let ref = makeRef()
      let heartbeat = RealtimeMessageV2(
        joinRef: nil, ref: ref, topic: "phoenix", event: "heartbeat", payload: [:])
      guard (try? enqueue(.text(try serializer.encodeText(heartbeat)))) != nil else { return }
      expectReply(ref)
      mirror.yieldHeartbeat(.sent)
      do {
        let latency = try await clock.measure {
          _ = try await withTimeout(configuration.heartbeatTimeout, clock: clock) {
            try await self.waitForReply(ref)
          }
        }
        mirror.yieldHeartbeat(.acknowledged(latency: latency))
      } catch is TimeoutError {
        guard generation == self.generation else { return }
        mirror.yieldHeartbeat(.timedOut)
        applyConnection(.heartbeatTimedOut)
        return
      } catch {
        return
      }
    }
  }

  // MARK: - Inbound

  private func handleText(_ text: String) {
    let message: RealtimeMessageV2
    do {
      message = try serializer.decodeText(text)
    } catch {
      logger.warning("dropping undecodable frame: \(error)")
      return
    }
    if message.event == "phx_reply", let ref = message.ref {
      deliverReply(message, ref: ref)
      return
    }
    guard let record = channels[message.topic] else { return }
    if let joinRef = message.joinRef, let current = record.joinRef, joinRef != current {
      logger.debug("dropping stale \(message.event) for \(message.topic)")
      return
    }
    switch message.event {
    case "phx_close":
      applyChannel(message.topic, .serverClosed)
    case "phx_error":
      applyChannel(message.topic, .serverErrored)
    case "presence_state":
      let change = channels[message.topic]?.presence.applyState(message.payload)
      mirror.yield(.message(message), to: message.topic)
      change.map { yieldPresence($0, to: message.topic) }
    case "presence_diff":
      let change = channels[message.topic]?.presence.applyDiff(message.payload)
      mirror.yield(.message(message), to: message.topic)
      if let change = change ?? nil { yieldPresence(change, to: message.topic) }
    default:
      // A postgres_changes error leaves the channel open while the server retries the binding.
      if message.event == "system", message.payload["status"] == "error",
        message.payload["extension"] != "postgres_changes"
      {
        let text = message.payload["message"]?.stringValue ?? "system error"
        applyChannel(message.topic, .systemError(message: text))
      }
      mirror.yield(.message(message), to: message.topic)
    }
  }

  private func yieldPresence(_ change: PresenceChange, to topic: String) {
    let state = channels[topic]?.presence.state ?? PresenceState()
    mirror.setPresence(topic, state)
    mirror.yield(.presenceChanged(change, state: state), to: topic)
  }

  private func handleBinary(_ data: Data) {
    do {
      let broadcast = try serializer.decodeBinary(data)
      mirror.yield(.broadcast(broadcast), to: broadcast.topic)
    } catch {
      logger.warning("dropping undecodable binary frame: \(error)")
    }
  }
}

extension ConnectionMachine.State {
  fileprivate var key: String {
    switch self {
    case .disconnected(let error): "disconnected:\(error?.message ?? "")"
    case .connecting(let attempt): "connecting:\(attempt)"
    case .connected: "connected"
    case .reconnecting(let attempt, let retryIn, _): "reconnecting:\(attempt):\(retryIn)"
    }
  }
}

extension ChannelMachine.State {
  fileprivate var key: String {
    switch self {
    case .unsubscribed: "unsubscribed"
    case .subscribing(let attempt, _): "subscribing:\(attempt)"
    case .subscribed: "subscribed"
    case .resubscribing(let attempt, let retryIn, _): "resubscribing:\(attempt):\(retryIn)"
    case .unsubscribing: "unsubscribing"
    case .failed(let error): "failed:\(error.message)"
    }
  }
}
