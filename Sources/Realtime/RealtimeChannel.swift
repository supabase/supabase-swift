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
import IssueReporting
import Logging

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
/// Obtain an instance from ``RealtimeClient/channel(_:options:)``, open the streams you want,
/// then call ``subscribe()``. Postgres-change and presence streams shape the join request, so
/// open them **before** subscribing; broadcast and system streams can be opened at any time.
///
/// ```swift
/// let channel = await client.channel("room:lobby") { config in
///   config.broadcast.receiveOwnBroadcasts = true
/// }
///
/// let messages = await channel.broadcasts(event: "message")
/// try await channel.subscribe()
///
/// for await payload in messages {
///   print(payload)
/// }
/// ```
///
/// The channel is an actor on its client's executor: every channel of one client, and the client
/// itself, form a single isolation domain. Cancelling the task that iterates a stream ends the
/// stream and removes its listener; removing the channel ends every stream.
///
/// ## Topics
/// ### Identity
/// - ``topic``
/// - ``config``
/// ### Status
/// - ``status``
/// - ``statusSnapshot``
/// - ``statusChanges``
/// ### Lifecycle
/// - ``subscribe()``
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
/// - ``presenceChanges()``
/// ### Postgres Changes
/// - ``postgresChanges(_:schema:table:filter:select:)-(AnyAction.Type,_,_,_,_)``
/// - ``postgresChanges(_:schema:table:filter:select:)-(InsertAction.Type,_,_,_,_)``
/// - ``postgresChanges(_:schema:table:filter:select:)-(UpdateAction.Type,_,_,_,_)``
/// - ``postgresChanges(_:schema:table:filter:select:)-(DeleteAction.Type,_,_,_,_)``
/// ### Broadcast Events
/// - ``broadcasts(event:)``
/// - ``broadcastData(event:)``
/// ### System Events
/// - ``systemMessages()``
public actor RealtimeChannel {
  /// The fully-qualified topic string sent to the Realtime server (e.g. `"realtime:room:lobby"`).
  public nonisolated let topic: String

  /// The channel's topic without the `realtime:` prefix, as expected by the
  /// broadcast REST endpoint (WebSocket frames use the full ``topic``).
  nonisolated let subTopic: String

  /// The channel's configuration, as passed to ``RealtimeClient/channel(_:options:)``.
  public nonisolated let config: RealtimeChannelConfig

  nonisolated let logger: Logging.Logger

  /// The client's executor owner, kept so the channel stays on it even after the client is gone.
  private let isolation: RealtimeExecutor

  public nonisolated var unownedExecutor: UnownedSerialExecutor {
    isolation.unownedExecutor
  }

  /// Weak: the client owns its channels, and a channel the app keeps after releasing the client
  /// must not keep the client (and its socket) alive.
  weak var client: RealtimeClient?

  nonisolated let maxRetryAttempts: Int
  nonisolated let timeout: Duration
  nonisolated let clock: any Clock<Duration>
  nonisolated let connectOnSubscribe: Bool
  nonisolated let retryDelay: @Sendable (_ attempt: Int) -> Duration

  // MARK: Subscription state

  enum SubscriptionState: CustomStringConvertible {
    case unsubscribed
    case subscribing(Task<Void, any Error>)
    case subscribed
    case unsubscribing(Task<Void, Never>)

    var description: String {
      switch self {
      case .unsubscribed: "unsubscribed"
      case .subscribing: "subscribing"
      case .subscribed: "subscribed"
      case .unsubscribing: "unsubscribing"
      }
    }

    var status: RealtimeChannelStatus {
      switch self {
      case .unsubscribed: .unsubscribed
      case .subscribing: .subscribing
      case .subscribed: .subscribed
      case .unsubscribing: .unsubscribing
      }
    }
  }

  var state: SubscriptionState = .unsubscribed
  nonisolated let statusMirror = StatusMirror<RealtimeChannelStatus>(.unsubscribed)

  /// The `ref` of the current join, tagged on every push and compared against the `join_ref`
  /// of server closes so a close for a previous incarnation of the topic is ignored.
  var joinRef: String?

  /// Resumed by the server's join confirmation; failed by a close, a reset, or cancellation.
  var joinWaiter: CheckedContinuation<Void, any Error>?

  /// Resumed by the server's `phx_close` while an unsubscribe waits for it.
  var closeWaiter: CheckedContinuation<Void, Never>?

  /// Set by a server close while a subscribe is in flight, so `subscribe()` throws
  /// `channelClosedByServer` instead of the bare `CancellationError` of the cancelled attempt.
  var closedByServerWhileSubscribing = false

  // MARK: Pushes

  /// A push waiting for its `phx_reply`.
  ///
  /// The slot is created before the frame goes out, so a reply can never arrive before anyone
  /// is waiting for it. A reply that lands before the caller parks its continuation is kept in
  /// `outcome` and handed over when the caller does.
  struct PendingPush {
    var waiter: CheckedContinuation<Void, any Error>?
    var outcome: Result<Void, any Error>?
  }

  /// Pushes waiting for a `phx_reply`, by `ref`.
  var pendingPushes: [String: PendingPush] = [:]

  // MARK: Listeners

  enum Listener {
    case broadcast(event: String, AsyncStream<JSONObject>.Continuation)
    case broadcastData(event: String, AsyncStream<Data>.Continuation)
    case postgres(PostgresJoinConfig, AsyncStream<AnyAction>.Continuation)
    case presence(AsyncStream<any PresenceAction>.Continuation)
    case system(AsyncStream<RealtimeMessageV2>.Continuation)

    func finish() {
      switch self {
      case .broadcast(_, let continuation): continuation.finish()
      case .broadcastData(_, let continuation): continuation.finish()
      case .postgres(_, let continuation): continuation.finish()
      case .presence(let continuation): continuation.finish()
      case .system(let continuation): continuation.finish()
      }
    }
  }

  /// Open streams, in registration order. The order fixes the `postgres_changes` array of the
  /// join payload.
  var listeners: [(id: UUID, listener: Listener)] = []

  /// The `postgres_changes` bindings the server echoed back on join, with their ids.
  var serverChanges: [PostgresJoinConfig] = []

  init(
    topic: String,
    config: RealtimeChannelConfig,
    client: RealtimeClient,
    logger: Logging.Logger,
    retryDelay: @escaping @Sendable (_ attempt: Int) -> Duration = RealtimeChannel
      .defaultRetryDelay
  ) {
    self.topic = topic
    self.subTopic =
      topic.hasPrefix("realtime:") ? String(topic.dropFirst("realtime:".count)) : topic
    self.config = config
    self.logger = logger
    self.client = client
    self.isolation = client.isolation
    self.maxRetryAttempts = client.options.maxRetryAttempts
    self.timeout = client.options.timeout
    self.clock = client.clock
    self.connectOnSubscribe = client.options.connectOnSubscribe
    self.retryDelay = retryDelay
  }

  deinit {
    for (_, listener) in listeners {
      listener.finish()
    }
    statusMirror.finish()
  }

  // MARK: - Status

  /// The current subscription status of the channel.
  public var status: RealtimeChannelStatus {
    statusMirror.current
  }

  /// The current subscription status, readable without an `await`.
  ///
  /// Written in the same synchronous stretch that updates ``status``, so it never lags behind.
  public nonisolated var statusSnapshot: RealtimeChannelStatus {
    statusMirror.current
  }

  /// An async stream that emits channel subscription status changes.
  ///
  /// The stream emits the current status immediately upon iteration and then each
  /// subsequent change. Cancelling the iterating task ends the stream.
  public nonisolated var statusChanges: AsyncStream<RealtimeChannelStatus> {
    statusMirror.stream()
  }

  func setState(_ newState: SubscriptionState) {
    logger.debug("State transition for '\(topic)': \(state) → \(newState)")
    state = newState
    statusMirror.update(newState.status)
  }

  // MARK: - Broadcast

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
      event: event, message: try JSONObject(message, encoder: encoder ?? JSONValue.encoder))
  }

  /// Sends a broadcast message with a raw `JSONObject` payload over the WebSocket.
  ///
  /// The channel must be subscribed. To broadcast without a subscription, use
  /// ``httpSend(event:message:timeout:)-(_,JSONObject,_)``.
  ///
  /// Returns as soon as the frame is sent, unless ``BroadcastJoinConfig/acknowledgeBroadcasts``
  /// is on: then it waits for the server's reply. Wrap the call in a `Task` to send without
  /// waiting; cancelling that task stops the wait, not the frame.
  ///
  /// - Parameters:
  ///   - event: The broadcast event name.
  ///   - message: A raw ``JSONObject`` payload.
  /// - Throws: ``RealtimeError`` with kind ``RealtimeError/Kind-swift.struct/notSubscribed``
  ///   when the channel is not subscribed, ``RealtimeError/Kind-swift.struct/timeout`` when no
  ///   reply arrived within the client's configured timeout, the server's reason as
  ///   ``RealtimeError/Kind-swift.struct/payloadTooLarge`` or
  ///   ``RealtimeError/Kind-swift.struct/server`` when it rejected the message, and
  ///   `CancellationError` when the awaiting task is cancelled.
  public func broadcast(event: String, message: JSONObject) async throws {
    guard case .subscribed = state, let client else {
      throw RealtimeError.notSubscribed
    }
    let ref = await client.makeRef()
    try await push(ref: ref) {
      await client.pushBroadcast(
        joinRef: joinRef, ref: ref, topic: topic, event: event, jsonPayload: message
      )
    }
  }

  /// Sends a binary broadcast message over the WebSocket.
  ///
  /// - Parameters:
  ///   - event: The broadcast event name.
  ///   - data: Raw binary data to send as the payload.
  /// - Throws: The errors of ``broadcast(event:message:)``.
  public func broadcast(event: String, data: Data) async throws {
    guard case .subscribed = state, let client else {
      throw RealtimeError.notSubscribed
    }
    let ref = await client.makeRef()
    try await push(ref: ref) {
      await client.pushBroadcast(
        joinRef: joinRef, ref: ref, topic: topic, event: event, binaryPayload: data
      )
    }
  }

  // MARK: - Presence

  /// Tracks the current client's presence state using a `Codable` value.
  ///
  /// The state is shared with all other clients on the same channel. Call this after subscribing.
  ///
  /// - Parameter state: A `Codable` value representing the client's presence state.
  /// - Throws: An error if the state cannot be encoded, or the errors of ``track(state:)``.
  public func track(_ state: some Codable) async throws {
    try await track(state: try JSONObject(state))
  }

  /// Tracks the current client's presence state using a raw `JSONObject`.
  ///
  /// The state is shared with all other clients on the same channel. Call this after subscribing.
  /// Waits for the server's reply when ``BroadcastJoinConfig/acknowledgeBroadcasts`` is on, as
  /// ``broadcast(event:message:)`` does.
  ///
  /// - Parameter state: A ``JSONObject`` representing the client's presence state.
  /// - Throws: The errors of ``broadcast(event:message:)``.
  public func track(state: JSONObject) async throws {
    guard case .subscribed = self.state else {
      throw RealtimeError.notSubscribed
    }
    try await pushAcknowledged(
      ChannelEvent.presence,
      payload: [
        "type": "presence",
        "event": "track",
        "payload": .object(state),
      ]
    )
  }

  /// Stops tracking the current client's presence state on the channel.
  ///
  /// Waits for the server's reply when ``BroadcastJoinConfig/acknowledgeBroadcasts`` is on, as
  /// ``broadcast(event:message:)`` does.
  ///
  /// - Throws: The errors of ``broadcast(event:message:)``.
  public func untrack() async throws {
    guard case .subscribed = state else {
      throw RealtimeError.notSubscribed
    }
    try await pushAcknowledged(
      ChannelEvent.presence,
      payload: [
        "type": "presence",
        "event": "untrack",
      ]
    )
  }

  // MARK: - Pushes

  /// Sends a protocol frame (`phx_join`, `phx_leave`, `access_token`) on this channel without
  /// waiting for its reply. Does nothing when the client is gone.
  func push(
    _ event: String, ref explicitRef: String? = nil, payload: JSONObject = [:]
  ) async {
    guard let client else { return }
    let ref: String
    if let explicitRef { ref = explicitRef } else { ref = await client.makeRef() }
    await client.push(message(ref: ref, event: event, payload: payload))
  }

  /// Sends `event` on this channel and waits for its reply when the channel acknowledges pushes.
  private func pushAcknowledged(_ event: String, payload: JSONObject) async throws {
    guard let client else {
      throw RealtimeError.notConnected
    }
    let ref = await client.makeRef()
    let message = message(ref: ref, event: event, payload: payload)
    try await push(ref: ref) { await client.push(message) }
  }

  private func message(ref: String, event: String, payload: JSONObject) -> RealtimeMessageV2 {
    RealtimeMessageV2(joinRef: joinRef, ref: ref, topic: topic, event: event, payload: payload)
  }

  /// Sends the frame `send` produces and, when the channel acknowledges pushes, waits for the
  /// server's reply to `ref`.
  ///
  /// The reply slot is registered before the frame goes out, in the same synchronous stretch,
  /// so an acknowledgement can never arrive before anyone is waiting for it.
  private func push(ref: String, send: () async -> Void) async throws {
    guard config.broadcast.acknowledgeBroadcasts else {
      await send()
      return
    }
    pendingPushes[ref] = PendingPush()
    defer { pendingPushes[ref] = nil }
    await send()
    do {
      try await withTimeout(timeout, clock: clock) {
        try await withTaskCancellationHandler {
          try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            awaitReply(for: ref, with: continuation)
          }
        } onCancel: {
          Task { await self.settlePush(ref: ref, with: .failure(CancellationError())) }
        }
      }
    } catch is TimeoutError {
      logger.debug("Push \(ref) on '\(topic)' timed out.")
      throw RealtimeError.pushTimeout
    }
  }

  /// Parks `continuation` until the reply for `ref` arrives, or resumes it at once when the
  /// reply is already in, the slot is gone, or the task is already cancelled.
  private func awaitReply(for ref: String, with continuation: CheckedContinuation<Void, any Error>)
  {
    guard let pending = pendingPushes[ref] else {
      continuation.resume(throwing: RealtimeError.notSubscribed)
      return
    }
    if let outcome = pending.outcome {
      pendingPushes[ref] = nil
      continuation.resume(with: outcome)
    } else if Task.isCancelled {
      pendingPushes[ref] = nil
      continuation.resume(throwing: CancellationError())
    } else {
      pendingPushes[ref]?.waiter = continuation
    }
  }

  /// Records the first outcome for `ref` and wakes its waiter. Later outcomes are ignored.
  private func settlePush(ref: String, with outcome: Result<Void, any Error>) {
    guard let pending = pendingPushes[ref] else { return }
    if let waiter = pending.waiter {
      pendingPushes[ref] = nil
      waiter.resume(with: outcome)
    } else if pending.outcome == nil {
      pendingPushes[ref]?.outcome = outcome
    }
  }

  private func didReceiveReply(ref: String, status: PushStatus, payload: JSONObject) {
    guard status == .error else {
      settlePush(ref: ref, with: .success(()))
      return
    }
    let reason =
      payload["response"]?.objectValue?["reason"]?.stringValue
      ?? payload["response"]?.stringValue
      ?? "The server rejected the push."
    settlePush(ref: ref, with: .failure(RealtimeError.ackError(reason: reason)))
  }

  /// Fails every push still waiting for a reply.
  func failPendingPushes(with error: RealtimeError) {
    for ref in pendingPushes.keys {
      settlePush(ref: ref, with: .failure(error))
    }
  }

  // MARK: - Incoming messages

  func onMessage(_ message: RealtimeMessageV2) async {
    do {
      switch message.eventType {
      case .system: handleSystem(message)
      case .reply: try handleReply(message)
      case .postgresChanges: try handlePostgresChanges(message)
      case .broadcast: try handleBroadcast(message)
      case .close: await handleClose(message)
      case .error: handleError(message)
      case .presenceDiff: try handlePresenceDiff(message)
      case .presenceState: try handlePresenceState(message)
      default: logger.debug("Received message with unhandled event type: \(message)")
      }
    } catch {
      logger.debug("Failed: \(error)")
    }
  }

  private func handleSystem(_ message: RealtimeMessageV2) {
    if message.status == .ok {
      didReceiveSubscribedOK()
    } else {
      logger.debug("Failed to subscribe to channel \(message.topic): \(message.payload)")
    }

    for case .system(let continuation) in listeners.map(\.listener) {
      continuation.yield(message)
    }
  }

  private func handleReply(_ message: RealtimeMessageV2) throws {
    guard
      let ref = message.ref,
      let status = message.payload["status"]?.stringValue
    else {
      throw RealtimeError.decoding("Received a reply with unexpected payload: \(message)")
    }

    didReceiveReply(ref: ref, status: PushStatus(rawValue: status), payload: message.payload)

    guard
      message.payload["response"]?.objectValue?.keys
        .contains(ChannelEvent.postgresChanges) == true
    else { return }

    serverChanges =
      try message.payload["response"]?
      .objectValue?["postgres_changes"]?
      .decode(as: [PostgresJoinConfig].self) ?? []
    didReceiveSubscribedOK()
  }

  private func handlePostgresChanges(_ message: RealtimeMessageV2) throws {
    guard let data = message.payload["data"] else {
      logger.debug("Expected \"data\" key in message payload.")
      return
    }

    let ids = message.payload["ids"]?.arrayValue?.compactMap(\.intValue) ?? []
    let action = try Self.makeAction(
      from: data.decode(as: PostgresActionData.self),
      rawMessage: message
    )

    let matched = serverChanges.filter { ids.contains($0.id) }
    for case .postgres(let filter, let continuation) in listeners.map(\.listener)
    where matched.contains(where: { $0 == filter }) {
      continuation.yield(action)
    }
  }

  private static func makeAction(
    from data: PostgresActionData,
    rawMessage: RealtimeMessageV2
  ) throws -> AnyAction {
    switch data.type {
    case "UPDATE":
      return .update(
        UpdateAction(
          columns: data.columns,
          commitTimestamp: data.commitTimestamp,
          record: data.record ?? [:],
          oldRecord: data.oldRecord ?? [:],
          rawMessage: rawMessage
        )
      )

    case "DELETE":
      return .delete(
        DeleteAction(
          columns: data.columns,
          commitTimestamp: data.commitTimestamp,
          oldRecord: data.oldRecord ?? [:],
          rawMessage: rawMessage
        )
      )

    case "INSERT":
      return .insert(
        InsertAction(
          columns: data.columns,
          commitTimestamp: data.commitTimestamp,
          record: data.record ?? [:],
          rawMessage: rawMessage
        )
      )

    default:
      throw RealtimeError.decoding("Unknown event type: \(data.type)")
    }
  }

  private func handleBroadcast(_ message: RealtimeMessageV2) throws {
    let payload = message.payload

    guard let event = payload["event"]?.stringValue else {
      throw RealtimeError.decoding("Expected 'event' key in 'payload' for broadcast event.")
    }

    deliverBroadcast(event: event, json: payload)
  }

  private func handleClose(_ message: RealtimeMessageV2) async {
    // Phoenix tags `phx_close` with the `join_ref` of the join it closes. A close for a previous
    // incarnation of this topic (e.g. a join abandoned during a reconnect) must not tear down
    // the current subscription (issue #1145, defect 3).
    guard didReceiveClose(joinRef: message.joinRef) else {
      return
    }
    await client?.remove(self)
    finishStreams()
  }

  private func handleError(_ message: RealtimeMessageV2) {
    logger.error(
      "Received an error in channel \(message.topic). That could be as a result of an invalid access token"
    )
    // Like `phx_close`, `phx_error` is tagged with the `join_ref` of the join it belongs to — an
    // error from a stale join must not tear down the current subscription (#1148). Errors
    // without a `join_ref` (e.g. auth errors before a join completes) are applied
    // unconditionally.
    didReceiveClose(joinRef: message.joinRef)
  }

  private func handlePresenceDiff(_ message: RealtimeMessageV2) throws {
    let joins = try message.payload["joins"]?.decode(as: [String: PresenceV2].self) ?? [:]
    let leaves = try message.payload["leaves"]?.decode(as: [String: PresenceV2].self) ?? [:]
    deliverPresence(joins: joins, leaves: leaves, rawMessage: message)
  }

  private func handlePresenceState(_ message: RealtimeMessageV2) throws {
    let joins = try message.payload.decode(as: [String: PresenceV2].self)
    deliverPresence(joins: joins, leaves: [:], rawMessage: message)
  }

  /// Called by the client when a binary broadcast frame (type 0x04) is received.
  func handleBinaryBroadcast(_ broadcast: DecodedBroadcast) {
    let event = broadcast.event

    switch broadcast.payload {
    case .json(let json):
      var message: JSONObject = [
        "event": .string(event),
        "payload": .object(json),
        "type": "broadcast",
      ]
      message["meta"] = broadcast.meta.map(JSONValue.object)
      deliverBroadcast(event: event, json: message)

    case .binary(let data):
      var delivered = false
      for case .broadcastData(let listening, let continuation) in listeners.map(\.listener)
      where Self.eventMatches(listening, event) {
        continuation.yield(data)
        delivered = true
      }
      if !delivered {
        logger.warning(
          "Received binary broadcast for event '\(event)' but no Data stream is open. Open one with broadcastData(event:) to receive Data."
        )
      }
    }
  }

  private func deliverBroadcast(event: String, json: JSONObject) {
    for case .broadcast(let listening, let continuation) in listeners.map(\.listener)
    where Self.eventMatches(listening, event) {
      continuation.yield(json)
    }
  }

  private func deliverPresence(
    joins: [String: PresenceV2], leaves: [String: PresenceV2], rawMessage: RealtimeMessageV2
  ) {
    for case .presence(let continuation) in listeners.map(\.listener) {
      continuation.yield(PresenceActionImpl(joins: joins, leaves: leaves, rawMessage: rawMessage))
    }
  }

  private static func eventMatches(_ listening: String, _ event: String) -> Bool {
    listening == "*" || listening.lowercased() == event.lowercased()
  }

  // MARK: - Listeners

  /// Registers `listener` and ends it when the stream's consumer goes away.
  ///
  /// `onTermination` runs on the consumer's context, so the removal hops back here once.
  func register<Element>(
    _ listener: Listener, terminating continuation: AsyncStream<Element>.Continuation
  ) {
    let id = UUID()
    listeners.append((id, listener))
    continuation.onTermination = { [weak self] _ in
      Task { await self?.removeListener(id) }
    }
  }

  private func removeListener(_ id: UUID) {
    listeners.removeAll { $0.id == id }
  }

  /// Ends every open stream and forgets its listener.
  func finishStreams() {
    let open = listeners
    listeners = []
    for (_, listener) in open {
      listener.finish()
    }
  }

  /// Whether a `presenceChanges()` stream is open: that is what turns presence on in the join
  /// payload, so the server only tracks presence for channels that read it.
  var hasPresenceListener: Bool {
    listeners.contains { if case .presence = $0.listener { true } else { false } }
  }

  /// The `postgres_changes` bindings of the open streams, in registration order.
  var clientChanges: [PostgresJoinConfig] {
    listeners.compactMap { if case .postgres(let config, _) = $0.listener { config } else { nil } }
  }

  /// Default exponential-backoff retry delay with ±25% jitter, capped at 30s.
  static let defaultRetryDelay: @Sendable (_ attempt: Int) -> Duration = { attempt in
    let baseDelay: Double = 1.0
    let maxDelay: Double = 30.0
    let backoffMultiplier: Double = 2.0

    let exponentialDelay = baseDelay * pow(backoffMultiplier, Double(attempt - 1))
    let cappedDelay = min(exponentialDelay, maxDelay)

    let jitterRange = cappedDelay * 0.25
    let jitter = Double.random(in: -jitterRange...jitterRange)

    return .seconds(max(0.1, cappedDelay + jitter))
  }
}
