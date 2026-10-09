//
//  EngineState.swift
//  Realtime
//
//  Created by Guilherme Souza on 09/10/26.
//

import Foundation
import HTTPTypes
import Helpers
import Logging

/// Every mutable value of Realtime: the machines, the channel records, the listeners, the reply
/// slots and the waiters. It lives in ``RealtimeEngine``'s lock and is only touched through
/// ``RealtimeEngine/withState(_:)``.
///
/// Its functions never await and never run code from outside the SDK. Work that must not happen
/// under the lock goes to ``later(_:)``, which the engine runs once the lock is released:
/// resuming a continuation, finishing a stream (it calls `onTermination`, which takes the lock),
/// cancelling a task (it runs cancellation handlers, which may take the lock), and logging (the
/// log handler is the app's code). Yields stay under the lock: they only enqueue, and keeping
/// them there keeps their order.
struct EngineState {
  enum ReplySlot {
    case expected
    case waiting(CheckedContinuation<RealtimeMessageV2, any Error>)
    case arrived(RealtimeMessageV2)
  }

  /// A sleeping task and its identity. A cancel only reaches the task after the lock is released,
  /// so a timer can wake after it was replaced; `fire` checks the id under the lock first.
  struct Timer {
    let id: UUID
    let task: Task<Void, Never>
  }

  struct ChannelRecord {
    let owner: ChannelOwner
    var config: RealtimeJoinConfig
    var state: ChannelMachine.State = .unsubscribed
    var joinRef: String?
    /// The server ids of the postgres bindings, by position, from the last successful join.
    var postgresChangeIDs: [Int] = []
    /// Resumed with `nil` on the next `resolveSubscribe`, or thrown into on `rejectSubscribe`.
    var subscribeWaiters: [UUID: CheckedContinuation<String?, any Error>] = [:]
    var pendingLeaveRef: String?
    /// Leaves that found another leave in flight, resumed once the channel stops unsubscribing.
    var leaveWaiters: [CheckedContinuation<String?, Never>] = []
    var joinTask: Task<Void, Never>?
    var rejoinTimer: Timer?
    var lingerTimer: Timer?
    var presence = PresenceTracker()
    var tokenPush = Throttle()
    var presencePush = Throttle()
  }

  /// One send per window per channel; a newer value inside the window replaces the pending one.
  struct Throttle {
    var window: Timer?
    var pending: JSONObject?
    var lastSent: JSONObject?
  }

  /// Listeners belong to one handle. Only the live owner's, the owner of the topic's record,
  /// receive anything; a handle's listeners can register before its record exists.
  struct ListenerKey: Hashable {
    var topic: String
    var owner: UUID
  }

  let configuration: RealtimeEngineConfiguration
  let clock: any Clock<Duration>
  let serializer = RealtimeSerializer()
  let logger: Logger
  /// For the tasks this state starts. Weak, so releasing the client can free the engine.
  weak var engine: RealtimeEngine?

  var connection: ConnectionMachine.State = .disconnected(nil)
  var channels: [String: ChannelRecord] = [:]
  var supervisor: Task<Void, Never>?
  var socket: (any WebSocketConnection)?
  var isShutDown = false
  /// Bumped on every supervisor start and every forced teardown, so callbacks from an older
  /// socket are ignored.
  var generation = 0
  var outbound: AsyncStream<WebSocketFrame>.Continuation?
  var wakeSignal: AsyncStream<Void>.Continuation?
  var idleTimer: Timer?
  /// One slot per ref a caller will wait on. A reply for a ref with no slot is dropped.
  var pendingReplies: [String: ReplySlot] = [:]
  var connectWaiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
  /// `addChannel` calls waiting for a retired owner's record to go, by topic.
  var removalWaiters: [String: [CheckedContinuation<Bool, Never>]] = [:]
  var refCounter = 0
  var tokens = TokenState()
  var tokenRefreshTimer: Timer?

  var connectionStatuses: [UUID: AsyncStream<RealtimeConnectionStatus>.Continuation] = [:]
  var channelStatuses: [ListenerKey: [UUID: AsyncStream<RealtimeChannelStatus>.Continuation]] =
    [:]
  var inbound: [ListenerKey: [UUID: AsyncStream<ChannelInbound>.Continuation]] = [:]
  var heartbeats: [UUID: AsyncStream<HeartbeatEvent>.Continuation] = [:]
  var connectionStates: [UUID: AsyncStream<ConnectionMachine.State>.Continuation] = [:]
  var channelStates: [String: [UUID: AsyncStream<ChannelMachine.State>.Continuation]] = [:]

  private var deferred: [@Sendable () -> Void] = []

  init(configuration: RealtimeEngineConfiguration, clock: any Clock<Duration>) {
    self.configuration = configuration
    self.clock = clock
    self.logger = configuration.logger
  }

  // MARK: - Deferred work

  mutating func later(_ work: @escaping @Sendable () -> Void) {
    deferred.append(work)
  }

  mutating func takeDeferred() -> [@Sendable () -> Void] {
    defer { deferred = [] }
    return deferred
  }

  mutating func cancel(_ task: Task<Void, Never>?) {
    if let task { later { task.cancel() } }
  }

  /// Runs `fire` under the lock after `delay`, with the timer's id to check against.
  func timer(
    after delay: Duration, fire: @escaping @Sendable (inout EngineState, UUID) -> Void
  ) -> Timer {
    let id = UUID()
    let clock = clock
    let task = Task { [weak engine] in
      try? await clock.sleep(for: delay)
      guard !Task.isCancelled, let engine else { return }
      engine.withState { fire(&$0, id) }
    }
    return Timer(id: id, task: task)
  }

  // MARK: - Connection

  mutating func applyConnection(_ event: ConnectionMachine.Event) {
    let before = connection.key
    let effects = ConnectionMachine.transition(
      &connection, event, configuration: configuration.connection)
    for effect in effects { perform(effect) }
    if connection.key != before {
      let state = connection
      connectionStatuses.values.forEach { $0.yield(state.publicStatus) }
      connectionStates.values.forEach { $0.yield(state) }
    }
    resolveConnectWaiters()
  }

  mutating func resolveConnectWaiters() {
    guard !connectWaiters.isEmpty else { return }
    let waiters = Array(connectWaiters.values)
    switch connection {
    case .connected:
      connectWaiters = [:]
      later { waiters.forEach { $0.resume() } }
    case .disconnected(let error):
      connectWaiters = [:]
      let failure = error ?? RealtimeError(kind: .notConnected, message: "disconnected")
      later { waiters.forEach { $0.resume(throwing: failure) } }
    case .connecting, .reconnecting:
      break
    }
  }

  private mutating func perform(_ effect: ConnectionMachine.Effect) {
    switch effect {
    case .openTransport:
      if supervisor == nil {
        generation += 1
        let generation = generation
        supervisor = Task { [weak engine] in await engine?.run(generation: generation) }
      } else {
        wakeSignal?.yield()
      }
    case .closeTransport(let code):
      if let socket {
        later { Task { await socket.close(code: code, reason: nil) } }
      } else {
        cancel(supervisor)
        supervisor = nil
        generation += 1
      }
    case .startHeartbeat, .stopHeartbeat, .scheduleRetry:
      break
    case .cancelRetry:
      wakeSignal?.yield()
    case .scheduleIdleDisconnect(let delay):
      cancel(idleTimer?.task)
      idleTimer = timer(after: delay) { state, id in
        guard state.idleTimer?.id == id else { return }
        state.idleTimer = nil
        state.applyConnection(.idleTimerFired)
      }
    case .cancelIdleDisconnect:
      cancel(idleTimer?.task)
      idleTimer = nil
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

  mutating func socketWentAway() {
    socket = nil
    outbound?.finish()
    outbound = nil
  }

  // MARK: - Channels

  func isOwner(_ owner: ChannelOwner, of topic: String) -> Bool {
    channels[topic]?.owner === owner
  }

  /// Creates the owner's record, or replaces the config of the owner's record. A retired owner,
  /// or a topic another owner holds, is a no-op.
  mutating func install(_ topic: String, owner: ChannelOwner, config: RealtimeJoinConfig) {
    guard !owner.isRetired else { return }
    if let record = channels[topic] {
      if record.owner === owner { channels[topic]?.config = config }
      return
    }
    channels[topic] = ChannelRecord(owner: owner, config: config)
    applyConnection(.channelAdded)
  }

  /// Forgets the owner's record after its leave, and finishes every stream of `owner`.
  mutating func forget(_ topic: String, owner: ChannelOwner) {
    defer {
      let waiters = removalWaiters.removeValue(forKey: topic) ?? []
      later { waiters.forEach { $0.resume(returning: true) } }
    }
    guard let record = channels[topic], record.owner === owner else { return }
    cancel(record.rejoinTimer?.task)
    cancel(record.joinTask)
    cancel(record.lingerTimer?.task)
    resetThrottles(topic)
    rejectSubscribe(
      topic, with: RealtimeError(kind: .notSubscribed, message: "channel \(topic) was removed"))
    let leaveWaiters = record.leaveWaiters
    later { leaveWaiters.forEach { $0.resume(returning: nil) } }
    channels[topic] = nil
    dropListeners(topic, owner: owner.id)
    let states = channelStates.removeValue(forKey: topic) ?? [:]
    later { states.values.forEach { $0.finish() } }
    if channels.isEmpty { applyConnection(.lastChannelRemoved) }
  }

  mutating func applyChannel(_ topic: String, _ event: ChannelMachine.Event) {
    guard var record = channels[topic] else { return }
    let before = record.state.key
    let effects = ChannelMachine.transition(
      &record.state, event, configuration: configuration.channel)
    channels[topic] = record
    for effect in effects { perform(effect, on: topic) }
    guard let record = channels[topic], record.state.key != before else { return }
    let state = record.state
    channelStatuses[ListenerKey(topic: topic, owner: record.owner.id)]?.values.forEach {
      $0.yield(state.publicStatus)
    }
    channelStates[topic]?.values.forEach { $0.yield(state) }
    if before == "unsubscribing" {
      let waiters = record.leaveWaiters
      channels[topic]?.leaveWaiters = []
      later { waiters.forEach { $0.resume(returning: nil) } }
    }
  }

  private mutating func perform(_ effect: ChannelMachine.Effect, on topic: String) {
    switch effect {
    case .sendJoin:
      sendJoin(topic)
    case .sendLeave:
      sendLeave(topic)
    case .scheduleRejoin(let delay):
      cancel(channels[topic]?.rejoinTimer?.task)
      let rejoin = timer(after: delay) { state, id in
        guard state.channels[topic]?.rejoinTimer?.id == id else { return }
        state.channels[topic]?.rejoinTimer = nil
        state.applyChannel(topic, .rejoinTimerFired)
      }
      channels[topic]?.rejoinTimer = rejoin
    case .cancelRejoin:
      cancel(channels[topic]?.rejoinTimer?.task)
      channels[topic]?.rejoinTimer = nil
    case .refreshToken:
      Task { [weak engine] in
        guard let engine else { return }
        await engine.refreshAccessToken()
        engine.withState { $0.applyChannel(topic, .tokenRefreshed) }
      }
    case .emitResubscribed:
      yield(.resubscribed, to: topic)
    case .resolveSubscribe:
      let waiters = Array(channels[topic]?.subscribeWaiters.values ?? [:].values)
      channels[topic]?.subscribeWaiters = [:]
      later { waiters.forEach { $0.resume(returning: nil) } }
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
      finishInbound(topic)
    case .scheduleLinger(let delay):
      cancel(channels[topic]?.lingerTimer?.task)
      let linger = timer(after: delay) { state, id in
        guard state.channels[topic]?.lingerTimer?.id == id else { return }
        state.channels[topic]?.lingerTimer = nil
        state.applyChannel(topic, .lingerTimerFired)
      }
      channels[topic]?.lingerTimer = linger
    case .cancelLinger:
      cancel(channels[topic]?.lingerTimer?.task)
      channels[topic]?.lingerTimer = nil
    }
  }

  mutating func rejectSubscribe(_ topic: String, with error: RealtimeError) {
    let waiters = Array(channels[topic]?.subscribeWaiters.values ?? [:].values)
    channels[topic]?.subscribeWaiters = [:]
    later { waiters.forEach { $0.resume(throwing: error) } }
  }

  /// Starts a leave. Resumes `waiter` with the ref of the `phx_leave` to wait for, or `nil` when
  /// the leave is already over. A leave that finds another in flight waits for that one.
  mutating func beginLeave(_ topic: String, _ waiter: CheckedContinuation<String?, Never>) {
    if case .unsubscribing = channels[topic]?.state {
      channels[topic]?.leaveWaiters.append(waiter)
      return
    }
    applyChannel(topic, .unsubscribeRequested)
    guard case .unsubscribing = channels[topic]?.state else {
      later { waiter.resume(returning: nil) }
      return
    }
    guard let ref = channels[topic]?.pendingLeaveRef else {
      applyChannel(topic, .leaveCompleted)
      later { waiter.resume(returning: nil) }
      return
    }
    expectReply(ref)
    later { waiter.resume(returning: ref) }
  }

  // MARK: - Join and leave

  private mutating func sendJoin(_ topic: String) {
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
    let payload = RealtimeJoinPayload(
      config: record.config, accessToken: tokens.token,
      version: configuration.headers[.xClientInfo])
    guard let encoded = try? JSONObject(payload) else {
      later { [logger] in logger.error("failed to encode the phx_join payload for \(topic)") }
      return
    }
    let message = RealtimeMessageV2(
      joinRef: ref, ref: ref, topic: topic, event: "phx_join", payload: encoded)
    channels[topic]?.joinRef = ref
    cancel(channels[topic]?.joinTask)
    do {
      try enqueue(.text(try serializer.encodeText(message)))
    } catch {
      later { [logger] in logger.error("failed to send phx_join for \(topic): \(error)") }
      return
    }
    expectReply(ref)
    channels[topic]?.joinTask = Task { [weak engine] in
      await engine?.awaitJoinReply(topic, ref: ref)
    }
  }

  mutating func joinResult(_ topic: String, reply: RealtimeMessageV2)
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
    let verified = ChannelMachine.verify(declared: declared, replied: replied)
    if case .success(let ids) = verified { channels[topic]?.postgresChangeIDs = ids }
    return verified.map { ChannelMachine.JoinReply(postgresChangeIDs: $0) }
  }

  private mutating func sendLeave(_ topic: String) {
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
  func joinRefForPush(_ topic: String, owner: ChannelOwner) throws -> String {
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

  // MARK: - Throttled pushes

  mutating func pushAccessTokenToJoinedChannels() {
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
  mutating func throttledSend(
    _ topic: String, event: String, payload: JSONObject,
    keyPath: any WritableKeyPath<ChannelRecord, Throttle> & Sendable, window: Duration
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
    record[keyPath: keyPath].window = timer(after: window) { state, id in
      state.closeThrottleWindow(topic, event: event, keyPath: keyPath, window: window, id: id)
    }
    channels[topic] = record
    return ref
  }

  private mutating func closeThrottleWindow(
    _ topic: String, event: String,
    keyPath: any WritableKeyPath<ChannelRecord, Throttle> & Sendable,
    window: Duration, id: UUID
  ) {
    guard var record = channels[topic], record[keyPath: keyPath].window?.id == id else { return }
    record[keyPath: keyPath].window = nil
    let pending = record[keyPath: keyPath].pending
    record[keyPath: keyPath].pending = nil
    channels[topic] = record
    if let pending {
      _ = try? throttledSend(
        topic, event: event, payload: pending, keyPath: keyPath, window: window)
    }
  }

  private mutating func resetThrottles(_ topic: String) {
    cancel(channels[topic]?.tokenPush.window?.task)
    cancel(channels[topic]?.presencePush.window?.task)
    channels[topic]?.tokenPush = Throttle()
    channels[topic]?.presencePush = Throttle()
  }

  /// Refreshes `accessTokenRefreshLeeway` before the token's `exp`, since the server closes
  /// every channel the moment it expires.
  mutating func scheduleTokenRefresh(atLeast minimum: Duration = .zero) {
    cancel(tokenRefreshTimer?.task)
    tokenRefreshTimer = nil
    guard
      let due = tokens.refreshDelay(now: Date(), leeway: configuration.accessTokenRefreshLeeway)
    else { return }
    let delay = max(due, minimum)
    let id = UUID()
    let clock = clock
    let task = Task { [weak engine] in
      try? await clock.sleep(for: delay)
      guard !Task.isCancelled, let engine,
        engine.withState({ $0.tokenRefreshTimer?.id == id })
      else { return }
      if await engine.refreshAccessToken() {
        engine.withState { $0.pushAccessTokenToJoinedChannels() }
      }
    }
    tokenRefreshTimer = Timer(id: id, task: task)
  }

  // MARK: - Wire

  mutating func makeRef() -> String {
    refCounter += 1
    return String(refCounter)
  }

  /// Non-blocking, so it runs under the lock and frames go out in the order the state decided.
  func enqueue(_ frame: WebSocketFrame) throws {
    guard let outbound else {
      throw RealtimeError(kind: .notConnected, message: "socket is not connected")
    }
    outbound.yield(frame)
  }

  /// Call in the same critical section as the `enqueue` so the reply cannot land before it.
  mutating func expectReply(_ ref: String) {
    if case .waiting? = pendingReplies[ref] { return }
    pendingReplies[ref] = .expected
  }

  mutating func awaitReply(
    _ ref: String, _ waiter: CheckedContinuation<RealtimeMessageV2, any Error>
  ) {
    if case .arrived(let message)? = pendingReplies[ref] {
      pendingReplies[ref] = nil
      later { waiter.resume(returning: message) }
    } else if Task.isCancelled {
      later { waiter.resume(throwing: CancellationError()) }
    } else {
      pendingReplies[ref] = .waiting(waiter)
    }
  }

  mutating func cancelReply(_ ref: String) {
    if case .waiting(let waiter)? = pendingReplies.removeValue(forKey: ref) {
      later { waiter.resume(throwing: CancellationError()) }
    }
  }

  private mutating func deliverReply(_ message: RealtimeMessageV2, ref: String) {
    switch pendingReplies[ref] {
    case .waiting(let waiter)?:
      pendingReplies[ref] = nil
      later { waiter.resume(returning: message) }
    case .expected?:
      pendingReplies[ref] = .arrived(message)
    case .arrived?, nil:
      break
    }
  }

  private mutating func failPendingReplies() {
    let slots = pendingReplies.values
    pendingReplies = [:]
    let error = RealtimeError(kind: .notConnected, message: "socket closed before the reply")
    for case .waiting(let waiter) in slots { later { waiter.resume(throwing: error) } }
  }

  // MARK: - Inbound

  mutating func handle(_ message: RealtimeMessageV2) {
    if message.event == "phx_reply", let ref = message.ref {
      deliverReply(message, ref: ref)
      return
    }
    guard let record = channels[message.topic] else { return }
    if let joinRef = message.joinRef, let current = record.joinRef, joinRef != current {
      later { [logger] in logger.debug("dropping stale \(message.event) for \(message.topic)") }
      return
    }
    switch message.event {
    case "phx_close":
      applyChannel(message.topic, .serverClosed)
    case "phx_error":
      applyChannel(message.topic, .serverErrored)
    case "presence_state":
      let change = channels[message.topic]?.presence.applyState(message.payload)
      yield(.message(message), to: message.topic)
      change.map { yieldPresence($0, to: message.topic) }
    case "presence_diff":
      let change = channels[message.topic]?.presence.applyDiff(message.payload)
      yield(.message(message), to: message.topic)
      if let change = change ?? nil { yieldPresence(change, to: message.topic) }
    default:
      // A postgres_changes error leaves the channel open while the server retries the binding.
      if message.event == "system", message.payload["status"] == "error",
        message.payload["extension"] != "postgres_changes"
      {
        let text = message.payload["message"]?.stringValue ?? "system error"
        applyChannel(message.topic, .systemError(message: text))
      }
      yield(.message(message), to: message.topic)
    }
  }

  private mutating func yieldPresence(_ change: PresenceChange, to topic: String) {
    let state = channels[topic]?.presence.state ?? PresenceState()
    yield(.presenceChanged(change, state: state), to: topic)
  }

  // MARK: - Listeners

  func liveKey(_ topic: String) -> ListenerKey? {
    channels[topic].map { ListenerKey(topic: topic, owner: $0.owner.id) }
  }

  func yield(_ value: ChannelInbound, to topic: String) {
    guard let key = liveKey(topic) else { return }
    inbound[key]?.values.forEach { $0.yield(value) }
  }

  func yieldHeartbeat(_ event: HeartbeatEvent) {
    heartbeats.values.forEach { $0.yield(event) }
  }

  /// Finishes the live owner's data streams on the topic.
  mutating func finishInbound(_ topic: String) {
    guard let key = liveKey(topic) else { return }
    let continuations = inbound.removeValue(forKey: key) ?? [:]
    later { continuations.values.forEach { $0.finish() } }
  }

  /// Finishes every status and data stream of `owner` on the topic.
  mutating func dropListeners(_ topic: String, owner: UUID) {
    let key = ListenerKey(topic: topic, owner: owner)
    let statuses = channelStatuses.removeValue(forKey: key) ?? [:]
    let data = inbound.removeValue(forKey: key) ?? [:]
    later {
      statuses.values.forEach { $0.finish() }
      data.values.forEach { $0.finish() }
    }
  }

  /// Finishes every stream, after a last `.disconnected` or `.unsubscribed` on status streams,
  /// and makes every later stream end at once.
  mutating func shutDown() {
    isShutDown = true
    connectionStatuses.values.forEach { $0.yield(.disconnected(nil)) }
    let statuses = channelStatuses.values.flatMap(\.values)
    statuses.forEach { $0.yield(.unsubscribed) }
    let connections = Array(connectionStatuses.values)
    let beats = Array(heartbeats.values)
    let data = inbound.values.flatMap(\.values)
    connectionStatuses = [:]
    channelStatuses = [:]
    heartbeats = [:]
    inbound = [:]
    later {
      connections.forEach { $0.finish() }
      statuses.forEach { $0.finish() }
      beats.forEach { $0.finish() }
      data.forEach { $0.finish() }
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
