//
//  RealtimeEngine.swift
//  Realtime
//
//  Created by Guilherme Souza on 06/10/26.
//

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
    var config: RealtimeJoinConfig
    var state: ChannelMachine.State = .unsubscribed
    var joinRef: String?
    var postgresChangeIDs: [Int] = []
    var subscribeWaiters: [CheckedContinuation<Void, any Error>] = []
    var pendingLeaveRef: String?
    var joinTask: Task<Void, Never>?
    var rejoinTask: Task<Void, Never>?
    var lingerTask: Task<Void, Never>?
  }

  private struct ListenerRegistry {
    var inbound: [String: [UUID: AsyncStream<ChannelInbound>.Continuation]] = [:]
    var channelStates: [String: [UUID: AsyncStream<ChannelMachine.State>.Continuation]] = [:]
    var connectionStates: [UUID: AsyncStream<ConnectionMachine.State>.Continuation] = [:]
  }

  private let configuration: RealtimeEngineConfiguration
  private let transport: any WebSocketTransport
  private let clock: any Clock<Duration>
  private let serializer = RealtimeSerializer()
  private let logger: Logger
  private var registry = ListenerRegistry()

  private var connection: ConnectionMachine.State = .disconnected(nil)
  private var channels: [String: ChannelRecord] = [:]
  private var supervisor: Task<Void, Never>?
  /// Bumped on every supervisor start and every forced teardown, so callbacks from an older
  /// socket are ignored.
  private var generation = 0
  private var socket: (any WebSocketConnection)?
  private var outbound: AsyncStream<WebSocketFrame>.Continuation?
  private var wakeSignal: AsyncStream<Void>.Continuation?
  private var idleTask: Task<Void, Never>?
  /// One slot per ref a caller will wait on. A reply for a ref with no slot is dropped: either it
  /// is late (the waiter timed out) or nobody awaits it (a push sent without a reply, a leave the
  /// machine sent on its own).
  private var pendingReplies: [String: ReplySlot] = [:]
  private var connectWaiters: [CheckedContinuation<Void, any Error>] = []

  var pendingReplyCount: Int { pendingReplies.count }
  private var refCounter = 0
  private var accessToken: String?

  package init(
    configuration: RealtimeEngineConfiguration,
    transport: any WebSocketTransport,
    clock: any Clock<Duration> = ContinuousClock()
  ) {
    self.configuration = configuration
    self.transport = transport
    self.clock = clock
    self.logger = configuration.logger
  }

  // MARK: - Connection API

  package var connectionState: ConnectionMachine.State { connection }

  /// Returns once the socket is connected. Throws the fatal error when the upgrade is refused
  /// for good (401, 403, 404), and `.notConnected` when `disconnect()` wins the race.
  package func connect() async throws {
    switch connection {
    case .connected: return
    case .disconnected, .reconnecting: applyConnection(.connectRequested)
    case .connecting: break
    }
    try await withCheckedThrowingContinuation { connectWaiters.append($0) }
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

  // MARK: - Channel API

  package func addChannel(_ topic: String, config: RealtimeJoinConfig = RealtimeJoinConfig()) {
    guard channels[topic] == nil else { return }
    channels[topic] = ChannelRecord(config: config)
    applyConnection(.channelAdded)
  }

  package func removeChannel(_ topic: String) async {
    guard channels[topic] != nil else { return }
    await unsubscribe(topic)
    channels[topic]?.rejoinTask?.cancel()
    channels[topic]?.joinTask?.cancel()
    channels[topic]?.lingerTask?.cancel()
    rejectSubscribe(
      topic, with: RealtimeError(kind: .notSubscribed, message: "channel \(topic) was removed"))
    channels[topic] = nil
    registry.inbound[topic]?.values.forEach { $0.finish() }
    registry.inbound[topic] = nil
    registry.channelStates[topic]?.values.forEach { $0.finish() }
    registry.channelStates[topic] = nil
    if channels.isEmpty { applyConnection(.lastChannelRemoved) }
  }

  package func channelState(_ topic: String) -> ChannelMachine.State? {
    channels[topic]?.state
  }

  /// The server ids of the channel's postgres bindings, by position, from the last join.
  package func postgresChangeIDs(_ topic: String) -> [Int] {
    channels[topic]?.postgresChangeIDs ?? []
  }

  /// Returns once the join is acknowledged. Throws the server's reason for a fatal join error,
  /// or `.notSubscribed` when the channel is unsubscribed before the join completes.
  package func subscribe(_ topic: String) async throws {
    guard channels[topic] != nil else {
      throw RealtimeError(kind: .notSubscribed, message: "unknown channel \(topic)")
    }
    applyChannel(topic, .subscribeRequested)
    if channels[topic]?.state.isSubscribed == true { return }
    try await withCheckedThrowingContinuation { channels[topic]?.subscribeWaiters.append($0) }
  }

  /// Sends the leave and returns once the server replied, the reply timed out, or the socket
  /// was already gone.
  package func unsubscribe(_ topic: String) async {
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

  /// Every message on the topic, unbounded. Ending the iteration removes the listener.
  package func inbound(_ topic: String) -> AsyncStream<ChannelInbound> {
    let (stream, continuation) = AsyncStream<ChannelInbound>.makeStream(
      bufferingPolicy: .unbounded)
    let id = UUID()
    continuation.onTermination = { [weak self] _ in
      Task { await self?.forgetListener { $0.inbound[topic]?[id] = nil } }
    }
    registry.inbound[topic, default: [:]][id] = continuation
    return stream
  }

  package func listenerCount(_ topic: String) -> Int {
    registry.inbound[topic]?.count ?? 0
  }

  private func forgetListener(_ remove: @Sendable (inout ListenerRegistry) -> Void) {
    remove(&registry)
  }

  /// Sends a push on a subscribed channel. With `awaitReply` it returns the reply payload, or
  /// throws `.timeout`, `.notConnected` when the socket goes away first, or the server's ack
  /// error.
  @discardableResult
  package func send(
    _ topic: String, event: String, payload: JSONObject, awaitReply: Bool
  ) async throws -> JSONObject? {
    let joinRef = try joinRefForPush(topic)
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
    _ topic: String, event: String, data: Data, awaitReply: Bool = false
  ) async throws {
    let joinRef = try joinRefForPush(topic)
    let ref = makeRef()
    let frame = try serializer.encodeBroadcastPush(
      joinRef: joinRef, ref: ref, topic: topic, event: event, binaryPayload: data)
    try enqueue(.binary(frame))
    guard awaitReply else { return }
    expectReply(ref)
    _ = try await awaitAcknowledgement(ref: ref)
  }

  /// Stores the token for the next join and pushes it to every joined channel.
  package func setAuth(_ token: String?) {
    accessToken = token
    guard let token, connection.isConnected else { return }
    for (topic, record) in channels where record.state.isSubscribed {
      let message = RealtimeMessageV2(
        joinRef: record.joinRef, ref: makeRef(), topic: topic, event: "access_token",
        payload: ["access_token": .string(token)])
      try? enqueue(.text(try serializer.encodeText(message)))
    }
  }

  // MARK: - Machines

  private func applyConnection(_ event: ConnectionMachine.Event) {
    let before = connection.key
    let effects = ConnectionMachine.transition(
      &connection, event, configuration: configuration.connection)
    for effect in effects { perform(effect) }
    if connection.key != before {
      let state = connection
      registry.connectionStates.values.forEach { $0.yield(state) }
    }
    resolveConnectWaiters()
  }

  private func resolveConnectWaiters() {
    guard !connectWaiters.isEmpty else { return }
    switch connection {
    case .connected:
      let waiters = connectWaiters
      connectWaiters = []
      waiters.forEach { $0.resume() }
    case .disconnected(let error):
      let waiters = connectWaiters
      connectWaiters = []
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
      registry.channelStates[topic]?.values.forEach { $0.yield(state) }
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
      registry.inbound[topic]?.values.forEach { $0.yield(.resubscribed) }
    case .resolveSubscribe:
      let waiters = channels[topic]?.subscribeWaiters ?? []
      channels[topic]?.subscribeWaiters = []
      waiters.forEach { $0.resume() }
    case .rejectSubscribe:
      let error =
        channels[topic]?.state.error
        ?? RealtimeError(kind: .notSubscribed, message: "channel \(topic) was unsubscribed")
      rejectSubscribe(topic, with: error)
    case .resendPresenceTrack:
      break
    case .finishDataStreams:
      registry.inbound[topic]?.values.forEach { $0.finish() }
      registry.inbound[topic] = nil
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
    let waiters = channels[topic]?.subscribeWaiters ?? []
    channels[topic]?.subscribeWaiters = []
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
    guard let record = channels[topic] else { return }
    let ref = makeRef()
    let payload = RealtimeJoinPayload(
      config: record.config, accessToken: accessToken,
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
      let reply = try await withTimeout(configuration.timeout, clock: clock) {
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
      channels[topic]?.postgresChangeIDs = ids
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

  private func joinRefForPush(_ topic: String) throws -> String {
    guard let record = channels[topic], record.state.isSubscribed, let joinRef = record.joinRef
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

  private func refreshAccessToken() async {
    guard let provider = configuration.accessToken else { return }
    if let token = try? await provider() { accessToken = token }
  }

  // MARK: - Supervisor

  private func run(generation: Int) async {
    defer { if self.generation == generation { supervisor = nil } }
    while !Task.isCancelled, generation == self.generation {
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
      guard generation == self.generation else {
        await connected.close(code: .normalClosure, reason: nil)
        return
      }
      let (frames, continuation) = AsyncStream<WebSocketFrame>.makeStream(
        bufferingPolicy: .unbounded)
      socket = connected
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
    socket = nil
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
      do {
        _ = try await withTimeout(configuration.heartbeatTimeout, clock: clock) {
          try await self.waitForReply(ref)
        }
      } catch is TimeoutError {
        guard generation == self.generation else { return }
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
    default:
      if message.event == "system", message.payload["status"] == "error" {
        let text = message.payload["message"]?.stringValue ?? "system error"
        applyChannel(message.topic, .systemError(message: text))
      }
      registry.inbound[message.topic]?.values.forEach { $0.yield(.message(message)) }
    }
  }

  private func handleBinary(_ data: Data) {
    do {
      let broadcast = try serializer.decodeBinary(data)
      registry.inbound[broadcast.topic]?.values.forEach { $0.yield(.broadcast(broadcast)) }
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
