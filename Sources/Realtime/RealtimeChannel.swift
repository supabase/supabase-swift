//
//  RealtimeChannel.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import ConcurrencyExtras
public import Foundation
import HTTPTypes
import Helpers
import Logging
import Phoenix

/// Configuration for a ``RealtimeChannel``.
///
/// Pass a builder closure to ``RealtimeClient/channel(_:options:)`` to customize
/// broadcast, presence, and privacy settings before subscribing.
///
/// ## Topics
/// ### Configuration Properties
/// - ``broadcast``
/// - ``presence``
/// - ``isPrivate``
public struct RealtimeChannelConfig: Sendable {
  /// Configuration for the broadcast feature of the channel.
  public var broadcast: BroadcastJoinConfig

  /// Configuration for the presence feature of the channel.
  public var presence: PresenceJoinConfig

  /// Whether the channel is private.
  ///
  /// Private channels enforce access control via RLS policies defined in your database.
  /// See the [Realtime authorization guide](https://supabase.com/docs/guides/realtime/authorization)
  /// for details.
  public var isPrivate: Bool
}

/// A Realtime channel that joins a topic and delivers its events as `AsyncStream`s.
///
/// Get one from ``RealtimeClient/channel(_:options:)``, make the streams you want, then call
/// ``subscribeWithError()``. Postgres change and presence streams shape the join request, so make
/// them before subscribing. Broadcast, status, and system streams can be made at any time.
///
/// ```swift
/// let channel = client.channel("room:lobby") { config in
///   config.broadcast.receiveOwnBroadcasts = true
/// }
///
/// let messages = channel.broadcastStream(event: "message")
/// try await channel.subscribeWithError()
///
/// for await payload in messages {
///   print(payload)
/// }
/// ```
///
/// A stream ends when the task that reads it is cancelled, or when the channel is removed from
/// its client. Two streams on the same event each get every message.
///
/// ## Topics
/// ### Identity
/// - ``topic``
/// - ``config``
/// ### Status
/// - ``status``
/// - ``statusChange``
/// ### Lifecycle
/// - ``subscribeWithError()``
/// - ``unsubscribe()``
/// ### Broadcasting
/// - ``broadcast(event:message:encoder:)``
/// - ``broadcast(event:message:)``
/// - ``broadcast(event:data:)``
/// - ``httpSend(event:message:timeout:)-(_,Codable,_)``
/// - ``httpSend(event:message:timeout:)-(_,JSONObject,_)``
/// - ``httpSend(event:data:timeout:)``
/// ### Presence
/// - ``track(_:)``
/// - ``track(state:)``
/// - ``untrack()``
/// - ``presenceChange()``
/// ### Postgres Changes
/// - ``postgresChange(_:schema:table:filter:select:)-(AnyAction.Type,_,_,_,_)``
/// - ``postgresChange(_:schema:table:filter:select:)-(InsertAction.Type,_,_,_,_)``
/// - ``postgresChange(_:schema:table:filter:select:)-(UpdateAction.Type,_,_,_,_)``
/// - ``postgresChange(_:schema:table:filter:select:)-(DeleteAction.Type,_,_,_,_)``
/// ### Broadcast Events
/// - ``broadcastStream(event:)``
/// - ``broadcastDataStream(event:)``
/// ### System Events
/// - ``system()``
public final class RealtimeChannel: Sendable {
  /// The topic sent to the Realtime server, such as `"realtime:room:lobby"`.
  public let topic: String

  /// The channel's configuration, as passed to ``RealtimeClient/channel(_:options:)``.
  public let config: RealtimeChannelConfig

  /// The topic without the `realtime:` prefix, as the REST broadcast endpoint expects it.
  let subTopic: String
  let connection: RealtimeConnection
  let state = LockIsolated(State())

  var logger: Logging.Logger { connection.options.logger }

  struct State: Sendable {
    var phase: Phase = .idle
    var streams = StreamRegistry()
    var serverChanges: [PostgresJoinConfig] = []
    var sentChanges: [PostgresJoinConfig] = []
    var publishedStatus: RealtimeChannelStatus = .unsubscribed
    var nextGeneration: UInt64 = 0
    var isRemoving = false

    var status: RealtimeChannelStatus {
      switch phase {
      case .idle, .removed: .unsubscribed
      case .attached(let attachment) where attachment.leaving != nil: .unsubscribing
      case .attached(let attachment): RealtimeChannelStatus(attachment.inner.status)
      }
    }

    /// Yielding under the lock keeps the stream order equal to the state order.
    mutating func publishStatus() {
      let current = status
      guard current != publishedStatus else { return }
      publishedStatus = current
      streams.yieldStatus(current)
    }

    mutating func endAttachment() {
      if case .attached(let attachment) = phase { attachment.pump.cancel() }
      phase = .idle
      serverChanges = []
    }

    func attachment(_ generation: UInt64) -> Attachment? {
      if case .attached(let attachment) = phase, attachment.generation == generation {
        attachment
      } else {
        nil
      }
    }
  }

  enum Phase: Sendable {
    case idle
    case attached(Attachment)
    case removed
  }

  /// A closed Phoenix channel cannot join again, so every subscribe after an unsubscribe makes a
  /// new attachment.
  struct Attachment: Sendable {
    let generation: UInt64
    let inner: Phoenix.Channel
    let pump: Task<Void, Never>
    var subscribing: Task<Void, any Error>?
    /// The callers waiting on `subscribing`. The last one to be cancelled cancels it.
    var waiters = 1
    var leaving: Task<Void, Never>?
    var joins = 0
    var joinToken: String?
    var sentToken: String?
    var joinsAtSend = 0
    var serverToken: String?

    /// Phoenix flushes the messages it held while the connection was down after the next join
    /// reply, so a token sent before that join can reach the server after the join's token.
    mutating func joined() {
      guard sentToken == nil || joinsAtSend < joins else { return }
      serverToken = sentToken == nil || sentToken == joinToken ? joinToken : nil
    }

    /// Starts the leave unless one runs already, and returns it. The leave ends the attachment
    /// once the server replied or the leave timed out, so no caller has to wait for it.
    mutating func leave(from channel: RealtimeChannel) -> Task<Void, Never> {
      if let leaving { return leaving }
      let inner = inner
      let generation = generation
      let started = Task {
        await inner.leave()
        channel.detach(generation)
      }
      leaving = started
      return started
    }
  }

  init(topic: String, config: RealtimeChannelConfig, connection: RealtimeConnection) {
    self.topic = topic
    self.subTopic =
      topic.hasPrefix("realtime:") ? String(topic.dropFirst("realtime:".count)) : topic
    self.config = config
    self.connection = connection
  }

  deinit {
    if case .attached(let attachment) = state.value.phase {
      attachment.pump.cancel()
      let inner = attachment.inner
      Task { await inner.leave() }
    }
    for sink in state.withValue({ $0.streams.removeAll() }) {
      sink.finish()
    }
  }

  /// The subscription status.
  public var status: RealtimeChannelStatus {
    state.value.status
  }

  /// Joins the channel and returns once the server accepted the join.
  ///
  /// Connects the client first unless `RealtimeClientOptions.connectOnSubscribe` is off. Calling
  /// it while a subscribe runs waits for that one. After the first join, the channel joins again
  /// on its own after a dropped connection, and ``status`` shows ``RealtimeChannelStatus/subscribing``
  /// meanwhile.
  ///
  /// With `RealtimeClientOptions.accessToken` set, the join first waits for a new token from the
  /// callback, at most `RealtimeClientOptions.timeout`, so a channel that subscribes right after
  /// sign-in joins with the new session.
  ///
  /// Each join attempt waits at least ``RealtimeClientOptions/defaultTimeout`` for the server's
  /// reply, even when `RealtimeClientOptions.timeout` is shorter, because the server can take that
  /// long to reject a private channel.
  ///
  /// The client reconnects on its own for as long as it takes, but a subscribe gives up after
  /// `RealtimeClientOptions.maxRetryAttempts` failed attempts. Each failed connection attempt
  /// counts, and so does each join that timed out or failed on an open connection. With
  /// `RealtimeClientOptions.connectOnSubscribe` off, each check that finds the client
  /// disconnected counts too. The first check runs at once, and the next ones 1, 2, 4 seconds
  /// apart and so on, up to 30 seconds.
  ///
  /// - Throws: ``RealtimeError`` with the server's reason when it rejected the join, kind
  ///   `.maxRetryAttemptsReached` after `maxRetryAttempts` failed attempts, kind
  ///   `.postgresChangesMismatch` when the server did not accept the `postgresChange` streams,
  ///   kind `.channelClosed` after the channel was removed, the error of
  ///   ``RealtimeClient/connect()`` when the client cannot connect, kind `.notConnected` when
  ///   ``RealtimeClient/disconnect(code:reason:)`` runs first, and `CancellationError` when the
  ///   calling task is cancelled. Cancelling the last waiting caller rolls the join back, and that
  ///   caller does not wait for the rollback. A subscribe during the rollback waits for it and
  ///   then joins again. A cancelled caller never waits for the rollback.
  public func subscribeWithError() async throws {
    while true {
      switch try nextSubscribeStep() {
      case .subscribed:
        return
      case .attempt(let attempt, let generation):
        try await wait(for: attempt, generation: generation)
        try Task.checkCancellation()
        return
      case .leave(let leaving):
        _ = await leaving.resultUnlessCancelled
        try Task.checkCancellation()
      case .rejoin(let inner):
        try await awaitRejoin(inner)
        try Task.checkCancellation()
      }
    }
  }

  private static let removedError = RealtimeError(
    kind: .channelClosed, message: "The channel was removed from its client.", isRetryable: false)

  private enum SubscribeStep {
    case subscribed
    case attempt(Task<Void, any Error>, generation: UInt64)
    case leave(Task<Void, Never>)
    /// Phoenix is joining again on its own.
    case rejoin(Phoenix.Channel)
  }

  /// A cancelled caller returns at once while other callers still wait on the attempt. The last
  /// one to go also cancels the attempt, and a leave rolls it back.
  private func wait(for attempt: Task<Void, any Error>, generation: UInt64) async throws {
    if let outcome = await attempt.resultUnlessCancelled {
      return try outcome.get()
    }
    if releaseWaiter(generation) {
      attempt.cancel()
    }
    throw CancellationError()
  }

  /// When no caller waits on the attempt anymore, turns it into a leave and returns `true`. A
  /// subscribe meanwhile then waits for the leave and joins again, instead of joining the
  /// cancelled attempt.
  private func releaseWaiter(_ generation: UInt64) -> Bool {
    state.withValue { state in
      guard var attachment = state.attachment(generation), attachment.subscribing != nil else {
        return false
      }
      attachment.waiters -= 1
      let isLast = attachment.waiters == 0
      if isLast {
        attachment.subscribing = nil
        _ = attachment.leave(from: self)
      }
      state.phase = .attached(attachment)
      state.publishStatus()
      return isLast
    }
  }

  /// Waits for Phoenix to join again, or for it to close the channel.
  private func awaitRejoin(_ inner: Phoenix.Channel) async throws {
    try await boundedAttempt(inner) {
      for await status in inner.statuses {
        if status == .joined { return }
        if case .closed = status { return }
      }
      // `statuses` ends only after `.closed`, or when this task is cancelled.
      throw CancellationError()
    }
  }

  private func nextSubscribeStep() throws -> SubscribeStep {
    try state.withValue { state in
      switch state.phase {
      case .removed:
        throw Self.removedError
      case .idle where state.isRemoving:
        throw Self.removedError
      case .idle:
        return attach(&state)
      case .attached(var attachment):
        if let leaving = attachment.leaving {
          return .leave(leaving)
        }
        if let subscribing = attachment.subscribing {
          attachment.waiters += 1
          state.phase = .attached(attachment)
          return .attempt(subscribing, generation: attachment.generation)
        }
        switch attachment.inner.status {
        case .joined:
          return .subscribed
        case .closed:
          state.endAttachment()
          if state.isRemoving { throw Self.removedError }
          return attach(&state)
        default:
          return .rejoin(attachment.inner)
        }
      }
    }
  }

  /// The pump subscribes to the inner streams before the join goes out, so it sees the first
  /// message.
  private func attach(_ state: inout State) -> SubscribeStep {
    let generation = state.nextGeneration
    state.nextGeneration += 1
    let inner = connection.socket.channel(
      Topic(topic),
      options: ChannelOptions(
        params: { [weak self] in self?.joinParams(generation: generation) ?? [:] },
        timeout: connection.joinTimeout,
        onRejectedJoin: .close
      )
    )
    let pump = startPump(inner, generation: generation)
    let attempt = Task { try await self.runSubscribe(inner, generation: generation) }
    state.phase = .attached(
      Attachment(generation: generation, inner: inner, pump: pump, subscribing: attempt))
    state.publishStatus()
    return .attempt(attempt, generation: generation)
  }

  private func runSubscribe(_ inner: Phoenix.Channel, generation: UInt64) async throws {
    do {
      let tokens = connection.tokens
      let mark = tokens.mark()
      let response = try await boundedAttempt(inner) {
        await tokens.refresh(startedAfter: mark)
        return try await inner.join()
      }
      if bindingsMismatch(in: response, generation: generation) {
        await unsubscribe(generation: generation)
        throw RealtimeError.postgresChangesMismatch
      }
      state.withValue { state in
        guard case .attached(var attachment) = state.phase, attachment.generation == generation
        else { return }
        attachment.subscribing = nil
        state.phase = .attached(attachment)
        state.publishStatus()
      }
    } catch {
      if let attachment = state.value.attachment(generation), attachment.leaving == nil {
        await inner.leave()
        detach(generation)
      }
      if error is CancellationError { throw error }
      if state.value.isRemoving { throw Self.removedError }
      throw RealtimeError(channelFailure: error)
    }
  }

  /// Connects first unless `connectOnSubscribe` is off, then runs `operation` until it returns,
  /// `maxRetryAttempts` attempts failed, or the socket stopped. Leaving the group cancels a join,
  /// and Phoenix rolls it back.
  private func boundedAttempt<Value: Sendable>(
    _ inner: Phoenix.Channel, _ operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    let options = connection.options
    let connection = connection
    let socketStatuses = connection.socket.statuses
    let stopStatuses = connection.socket.statuses
    let channelStatuses = inner.statuses
    return try await withThrowingTaskGroup(of: Value?.self) { group in
      group.addTask {
        if options.connectOnSubscribe {
          try await connection.connect()
        }
        return try await operation()
      }
      group.addTask {
        try await Self.failAfterAttempts(
          socket: socketStatuses, channel: channelStatuses, maxAttempts: options.maxRetryAttempts,
          idleChecks: options.connectOnSubscribe ? nil : connection)
        return nil
      }
      group.addTask {
        try await connection.failWhenSocketStops(
          stopStatuses, isConnecting: options.connectOnSubscribe)
        return nil
      }
      defer { group.cancelAll() }
      while let result = try await group.next() {
        if let result { return result }
      }
      throw CancellationError()
    }
  }

  /// Counts each failed connection attempt of the socket, and each join that failed on an open
  /// socket, after the first status of each stream. A dropped connection also errors the channel,
  /// so the channel side skips `.connectionLost` to count that failure once. Returns when the
  /// channel closes.
  ///
  /// With `idleChecks`, also counts each check that finds its socket disconnected with no
  /// failure, because nothing connects that socket meanwhile. The first check runs at once, and
  /// the next ones 1, 2, 4 seconds apart and so on up to 30, as release/v2's subscribe retries do.
  private static func failAfterAttempts(
    socket: AsyncStream<SocketStatus>, channel: AsyncStream<ChannelStatus>, maxAttempts: Int,
    idleChecks: RealtimeConnection?
  ) async throws {
    let failures = LockIsolated(0)
    let countFailure: @Sendable () throws -> Void = {
      let count = failures.withValue { failures in
        failures += 1
        return failures
      }
      if count >= maxAttempts { throw RealtimeError.maxRetryAttemptsReached }
    }
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        for await status in socket.dropFirst() {
          if case .waitingToReconnect = status { try countFailure() }
        }
      }
      if let idleChecks {
        group.addTask {
          for check in 1... {
            if case .disconnected(failure: nil) = idleChecks.socket.status { try countFailure() }
            try await idleChecks.options.clock.sleep(for: .seconds(min(30, 1 << min(check - 1, 5))))
          }
        }
      }
      group.addTask {
        var wasErrored: Bool?
        for await status in channel {
          switch status {
          case .closed:
            return
          case .errored(let failure):
            if wasErrored == false, failure != .connectionLost { try countFailure() }
            wasErrored = true
          default:
            wasErrored = false
          }
        }
      }
      defer { group.cancelAll() }
      try await group.next()
    }
  }

  /// Leaves the channel and returns once the server confirmed or the leave timed out.
  ///
  /// Streams stay open, and ``subscribeWithError()`` joins the channel again. The leave waits as
  /// long as a join attempt, at least ``RealtimeClientOptions/defaultTimeout``. Cancelling the
  /// calling task does not shorten the wait.
  public func unsubscribe() async {
    await unsubscribe(generation: nil)
  }

  /// With a `generation`, does nothing when a newer subscribe replaced that attachment.
  private func unsubscribe(generation expected: UInt64?) async {
    let leaving: Task<Void, Never>? = state.withValue { state in
      guard case .attached(var attachment) = state.phase else { return nil }
      if let expected, attachment.generation != expected { return nil }
      let leaving = attachment.leave(from: self)
      state.phase = .attached(attachment)
      state.publishStatus()
      return leaving
    }
    await leaving?.value
  }

  private func detach(_ generation: UInt64) {
    state.withValue { state in
      guard state.attachment(generation) != nil else { return }
      state.endAttachment()
      state.publishStatus()
    }
  }

  func remove() async {
    state.withValue { $0.isRemoving = true }
    await unsubscribe()
    let sinks = state.withValue { state in
      state.endAttachment()
      state.phase = .removed
      state.publishStatus()
      return state.streams.removeAll()
    }
    for sink in sinks {
      sink.finish()
    }
  }

  private func startPump(_ inner: Phoenix.Channel, generation: UInt64) -> Task<Void, Never> {
    let messages = inner.messages()
    let statuses = inner.statuses
    let joins = inner.joins
    return Task { [weak self] in
      await withTaskGroup(of: Void.self) { [weak self] group in
        group.addTask { [weak self] in
          for await message in messages { self?.receive(message, generation: generation) }
        }
        group.addTask { [weak self] in
          for await _ in statuses { self?.statusChanged(generation: generation) }
        }
        group.addTask { [weak self] in
          for await response in joins {
            self?.rejoined(response, generation: generation)
          }
        }
      }
    }
  }

  /// Decodes outside the lock, delivers under it. A route does not depend on the bindings it was
  /// computed from, so a stream opened or ended meanwhile gets the message or not by its own
  /// binding.
  private func receive(_ message: Phoenix.Message, generation: UInt64) {
    guard
      let snapshot = state.withValue({ state in
        state.attachment(generation).map { _ in (state.streams.bindings, state.serverChanges) }
      })
    else { return }
    let routed: ChannelRoute?
    do {
      routed = try routeMessage(message, bindings: snapshot.0, serverChanges: snapshot.1)
    } catch {
      logger.debug("Dropped a \(message.event) message on \(topic) that does not decode.")
      return
    }
    guard let routed else { return }
    if !routed.hasListeners {
      if case .binary = message.payload {
        logger.warning(
          "Received a binary broadcast on \(topic) but no Data stream is open. Open one with broadcastDataStream(event:) to receive Data."
        )
      }
      return
    }
    state.withValue { state in
      guard state.attachment(generation) != nil else { return }
      state.streams.deliver(routed)
    }
  }

  private func routeMessage(
    _ message: Phoenix.Message,
    bindings: [ChannelBinding],
    serverChanges: [PostgresJoinConfig]
  ) throws -> ChannelRoute? {
    switch message.payload {
    case .binary(let data) where message.event == ChannelEvent.broadcast:
      return route(try BroadcastFrameCodec.decode(data), bindings: bindings)
    case .binary(let data):
      return route(
        DecodedBroadcast(topic: topic, event: message.event, payload: .binary(data)),
        bindings: bindings)
    case .json:
      let realtimeMessage = RealtimeMessageV2(
        joinRef: nil, ref: nil, topic: topic, event: message.event,
        payload: message.payload.jsonObject)
      return try route(realtimeMessage, bindings: bindings, serverChanges: serverChanges)
    }
  }

  /// The status loop wakes on every inner change and publishes the value derived now, so a late
  /// wake-up publishes nothing stale.
  private func statusChanged(generation: UInt64) {
    state.withValue { state in
      guard let attachment = state.attachment(generation) else { return }
      if case .closed = attachment.inner.status, attachment.leaving == nil {
        state.endAttachment()
      }
      state.publishStatus()
    }
  }

  private func rejoined(_ response: Phoenix.Payload, generation: UInt64) {
    let tokens = connection.tokens
    let isRejoin = state.withValue { state in
      guard case .attached(var attachment) = state.phase, attachment.generation == generation
      else { return false }
      attachment.joined()
      state.phase = .attached(attachment)
      if attachment.serverToken != tokens.token { tokens.requestPush() }
      return attachment.subscribing == nil
    }
    guard isRejoin, bindingsMismatch(in: response, generation: generation) else { return }
    logger.error(
      "The server did not accept the postgres_changes bindings of \(topic) on rejoin. Unsubscribing."
    )
    Task { await self.unsubscribe(generation: generation) }
  }

  /// Stores the join reply's bindings and returns `true` when they differ from what the join
  /// sent. Runs for the same reply from the subscribe path and the pump, so it must stay
  /// idempotent.
  private func bindingsMismatch(in response: Phoenix.Payload, generation: UInt64) -> Bool {
    state.withValue { state in
      guard state.attachment(generation) != nil else { return false }
      let echoed: [PostgresJoinConfig]
      do {
        echoed = try serverChanges(fromJoinReply: response.jsonObject)
      } catch {
        logger.error("The join reply of \(topic) has postgres_changes in an unknown shape.")
        echoed = []
      }
      state.serverChanges = echoed
      return !postgresChangesMatch(sent: state.sentChanges, server: echoed)
    }
  }

  /// Phoenix calls it at every join attempt, when it encodes the frame.
  private func joinParams(generation: UInt64) -> Phoenix.JSONObject {
    let tokens = connection.tokens
    let version = connection.options.headers[.xClientInfo]
    return state.withValue { state in
      let accessToken = tokens.token
      if case .attached(var attachment) = state.phase, attachment.generation == generation {
        attachment.joins += 1
        attachment.joinToken = accessToken
        state.phase = .attached(attachment)
      }
      state.sentChanges = state.streams.postgresChanges
      do {
        return try joinPayload(
          config: config, bindings: state.streams.bindings, accessToken: accessToken,
          version: version
        ).phoenix
      } catch {
        logger.error("Failed to encode the join payload of \(topic).")
        return [:]
      }
    }
  }

  /// Sends a broadcast message with a `Codable` payload over the WebSocket.
  ///
  /// - Parameters:
  ///   - event: The broadcast event name.
  ///   - message: A `Codable` value to send as the message payload.
  ///   - encoder: The `JSONEncoder` used to serialize `message`. Defaults to the fixed internal
  ///     encoder (``JSONValue/encoder``) when `nil`.
  /// - Throws: An error if `message` cannot be encoded, or the errors of
  ///   ``broadcast(event:message:)``.
  public func broadcast(
    event: String, message: some Codable, encoder: JSONEncoder? = nil
  ) async throws {
    try await broadcast(
      event: event,
      message: try Helpers.JSONObject(message, encoder: encoder ?? Helpers.JSONValue.encoder))
  }

  /// Sends a broadcast message with a raw `JSONObject` payload over the WebSocket.
  ///
  /// The channel must be subscribed. To broadcast without a subscription, use
  /// ``httpSend(event:message:timeout:)-(_,JSONObject,_)``.
  ///
  /// Returns as soon as the frame is queued, unless ``BroadcastJoinConfig/acknowledgeBroadcasts``
  /// is on: then it waits for the server's reply. Cancelling the task stops the wait, not the
  /// frame.
  ///
  /// - Parameters:
  ///   - event: The broadcast event name.
  ///   - message: A raw ``JSONObject`` payload.
  /// - Throws: ``RealtimeError`` with kind `.notSubscribed` when the channel is not subscribed,
  ///   `.timeout` when no reply arrived within `RealtimeClientOptions.timeout`, the server's
  ///   reason as `.payloadTooLarge` or `.server` when it rejected the message, and
  ///   `CancellationError` when the task is cancelled.
  public func broadcast(event: String, message: Helpers.JSONObject) async throws {
    try await pushBroadcast(event: event) {
      try BroadcastFrameCodec.encodePush(
        joinRef: nil, ref: nil, topic: topic, event: event, jsonPayload: message)
    }
  }

  /// Sends a binary broadcast message over the WebSocket.
  ///
  /// - Parameters:
  ///   - event: The broadcast event name.
  ///   - data: Raw binary data to send as the payload.
  /// - Throws: The errors of ``broadcast(event:message:)``.
  public func broadcast(event: String, data: Data) async throws {
    try await pushBroadcast(event: event) {
      try BroadcastFrameCodec.encodePush(
        joinRef: nil, ref: nil, topic: topic, event: event, binaryPayload: data)
    }
  }

  /// The refs stay empty because ``SupabaseFrameCodec`` stamps them.
  private func pushBroadcast(event: String, template: () throws -> Data) async throws {
    let inner = try subscribedInner()
    let frame: Data
    do {
      frame = try template()
    } catch {
      throw RealtimeError.encoding("The broadcast '\(event)' could not be encoded.")
    }
    try await mappingChannelErrors {
      if config.broadcast.acknowledgeBroadcasts {
        try await inner.push(
          ChannelEvent.broadcast, .binary(frame), timeout: connection.options.timeout)
      } else {
        try await inner.send(ChannelEvent.broadcast, .binary(frame))
      }
    }
  }

  /// Tracks the current client's presence state using a `Codable` value.
  ///
  /// The state is shared with all other clients on the same channel. Call this after subscribing.
  ///
  /// - Parameter state: A `Codable` value representing the client's presence state.
  /// - Throws: An error if the state cannot be encoded, or the errors of ``track(state:)``.
  public func track(_ state: some Codable) async throws {
    try await track(state: try Helpers.JSONObject(state))
  }

  /// Tracks the current client's presence state using a raw `JSONObject`, and waits for the
  /// server's reply.
  ///
  /// - Parameter state: A ``JSONObject`` representing the client's presence state.
  /// - Throws: The errors of ``broadcast(event:message:)``.
  public func track(state: Helpers.JSONObject) async throws {
    try await pushPresence(["type": "presence", "event": "track", "payload": .object(state)])
  }

  /// Stops tracking the current client's presence state, and waits for the server's reply.
  ///
  /// - Throws: The errors of ``broadcast(event:message:)``.
  public func untrack() async throws {
    try await pushPresence(["type": "presence", "event": "untrack"])
  }

  private func pushPresence(_ payload: Helpers.JSONObject) async throws {
    let inner = try subscribedInner()
    try await mappingChannelErrors {
      try await inner.push(
        ChannelEvent.presence, .json(.object(payload.phoenix)),
        timeout: connection.options.timeout)
    }
  }

  /// The server replies only to an invalid token, with a `phx_close`.
  func sendAccessToken(_ token: String) async {
    let inner: Phoenix.Channel? = state.withValue { state in
      guard case .attached(var attachment) = state.phase, attachment.leaving == nil,
        attachment.inner.status == .joined, attachment.serverToken != token
      else { return nil }
      attachment.sentToken = token
      attachment.joinsAtSend = attachment.joins
      attachment.serverToken = token
      state.phase = .attached(attachment)
      return attachment.inner
    }
    guard let inner else { return }
    logger.debug("Updating auth token for channel \(topic)")
    try? await inner.send(
      ChannelEvent.accessToken, .json(.object(["access_token": .string(token)])))
  }

  private func subscribedInner() throws -> Phoenix.Channel {
    try state.withValue { state in
      guard case .attached(let attachment) = state.phase, attachment.leaving == nil,
        attachment.inner.status == .joined
      else { throw RealtimeError.notSubscribed }
      return attachment.inner
    }
  }

  private func mappingChannelErrors(_ operation: () async throws -> Void) async throws {
    do {
      try await operation()
    } catch let error as CancellationError {
      throw error
    } catch {
      throw RealtimeError(channelFailure: error)
    }
  }
}

extension Task {
  /// The task's result, or `nil` once the calling task is cancelled. `Task.result` ignores
  /// cancellation and waits for the task to end. Neither cancels the task.
  var resultUnlessCancelled: Result<Success, Failure>? {
    get async {
      let (outcomes, continuation) = AsyncStream<Result<Success, Failure>>.makeStream()
      Task<Void, Never> {
        continuation.yield(await result)
        continuation.finish()
      }
      for await outcome in outcomes {
        return outcome
      }
      return nil
    }
  }
}
