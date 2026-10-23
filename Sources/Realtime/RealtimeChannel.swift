//
//  RealtimeChannel.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import ConcurrencyExtras
public import Foundation
internal import HTTPTypes
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
/// - ``statusChanges()``
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

  nonisolated let timeout: Duration
  nonisolated let clock: any Clock<Duration>
  nonisolated let connectOnSubscribe: Bool

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

  /// The `ref` of the current join, tagged on every push and compared against the `join_ref`
  /// of server closes so a close for a previous incarnation of the topic is ignored.
  var joinRef: String?

  /// The access token the current `phx_join` was sent with, so a token stored while the join
  /// waits for its reply is still sent to the channel.
  var joinAccessToken: String?

  /// Resumed by the server's join confirmation; failed by a join error, a close, a reset, or
  /// cancellation.
  var joinWaiter: (ref: String, continuation: CheckedContinuation<Void, any Error>)?

  /// A join error that arrived while its `phx_join` was still being sent, before the attempt
  /// parked its waiter. The attempt for `ref` picks it up.
  var joinFailure: (ref: String, error: RealtimeError)?

  /// Callers that joined an in-flight subscribe. Each one is resumed by the shared attempt or by
  /// its own cancellation, which leaves the attempt running.
  var sharedSubscribeWaiters:
    [UUID: (task: Task<Void, any Error>, continuation: CheckedContinuation<Void, any Error>)] = [:]

  /// Resumed by the server's `phx_close` while an unsubscribe waits for it.
  var closeWaiter: CheckedContinuation<Void, Never>?

  /// The subscribe task a server close or ``RealtimeClient/disconnect(code:reason:)`` cancelled
  /// while it was in flight, and the error its caller gets. That attempt compares the task against
  /// its own so `subscribe()` throws `error` instead of the bare `CancellationError`, then clears
  /// it. A newer attempt never consumes it.
  var abortedSubscribe: (task: Task<Void, any Error>, error: RealtimeError)?

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
    case status(AsyncStream<RealtimeChannelStatus>.Continuation)

    func finish() {
      switch self {
      case .broadcast(_, let continuation): continuation.finish()
      case .broadcastData(_, let continuation): continuation.finish()
      case .postgres(_, let continuation): continuation.finish()
      case .presence(let continuation): continuation.finish()
      case .system(let continuation): continuation.finish()
      case .status(let continuation): continuation.finish()
      }
    }

    var binding: ChannelBinding {
      switch self {
      case .broadcast(let event, _): .broadcast(event: event)
      case .broadcastData(let event, _): .broadcastData(event: event)
      case .postgres(let change, _): .postgres(change)
      case .presence: .presence
      case .system: .system
      case .status: .status
      }
    }

    func yield(_ delivery: ChannelDelivery) {
      switch (self, delivery) {
      case (.broadcast(_, let continuation), .broadcast(let json)): continuation.yield(json)
      case (.broadcastData(_, let continuation), .broadcastData(let data)): continuation.yield(data)
      case (.postgres(_, let continuation), .postgres(let action)): continuation.yield(action)
      case (.presence(let continuation), .presence(let action)): continuation.yield(action)
      case (.system(let continuation), .system(let message)): continuation.yield(message)
      default: assertionFailure("route paired a \(delivery) delivery with a \(binding) stream")
      }
    }
  }

  /// Open streams, in registration order. The order fixes the `postgres_changes` array of the
  /// join payload, and indexes the deliveries of ``route(_:bindings:serverChanges:)``.
  var listeners: [(id: UUID, listener: Listener)] = []

  /// The `postgres_changes` bindings the server echoed back on join, with their ids.
  var serverChanges: [PostgresJoinConfig] = []

  // MARK: Presence

  /// The server's presence set for the current join. Diffs that arrive before the join's first
  /// `presence_state` wait in it for that state.
  var presence = PresenceTracker()

  init(
    topic: String,
    config: RealtimeChannelConfig,
    client: RealtimeClient,
    logger: Logging.Logger
  ) {
    self.topic = topic
    self.subTopic =
      topic.hasPrefix("realtime:") ? String(topic.dropFirst("realtime:".count)) : topic
    self.config = config
    self.logger = logger
    self.client = client
    self.isolation = client.isolation
    self.timeout = client.options.timeout
    self.clock = client.clock
    self.connectOnSubscribe = client.options.connectOnSubscribe
  }

  deinit {
    for (_, listener) in listeners {
      listener.finish()
    }
  }

  // MARK: - Status

  /// The current subscription status of the channel.
  public var status: RealtimeChannelStatus {
    state.status
  }

  /// An async stream that emits channel subscription status changes.
  ///
  /// The stream emits the current status immediately upon iteration and then each
  /// subsequent change. Cancelling the iterating task ends the stream; so does removing the
  /// channel from its client.
  public func statusChanges() -> AsyncStream<RealtimeChannelStatus> {
    let (stream, continuation) = AsyncStream<RealtimeChannelStatus>.makeStream(
      bufferingPolicy: .unbounded
    )
    register(.status(continuation), terminating: continuation)
    continuation.yield(status)
    return stream
  }

  func setState(_ newState: SubscriptionState) {
    logger.debug("State transition for '\(topic)': \(state) → \(newState)")
    let previous = status
    state = newState
    guard newState.status != previous else { return }
    // A new join waits for its own first presence state.
    if case .subscribing = newState {
      presence.reset()
    }
    for case .status(let continuation) in listeners.map(\.listener) {
      continuation.yield(newState.status)
    }
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
      case .close: await handleClose(message)
      case .error: handleError(message)
      case .presenceDiff: _ = presence.applyDiff(message.payload)
      case .presenceState: _ = presence.applyState(message.payload)
      case .postgresChanges, .broadcast: break
      default: logger.debug("Received message with unhandled event type: \(message)")
      }
      if let routed = try route(message, bindings: bindings, serverChanges: serverChanges) {
        deliver(routed)
      }
    } catch {
      logger.debug("Failed: \(error)")
    }
  }

  private func handleSystem(_ message: RealtimeMessageV2) {
    switch message.status {
    case .ok where message.joinRef == nil || message.joinRef == joinRef:
      didReceiveSubscribedOK()
    case .error:
      // The server reports a postgres-changes subscription it could not set up this way. The
      // join itself stands, so broadcast and presence keep working and the channel stays
      // subscribed.
      let reason = message.payload["message"]?.stringValue ?? "\(message.payload)"
      logger.error("Channel '\(topic)' reported an error: \(reason)")
    default:
      break
    }
  }

  private func handleReply(_ message: RealtimeMessageV2) throws {
    guard
      let ref = message.ref,
      let status = message.payload["status"]?.stringValue
    else {
      throw RealtimeError.decoding("Received a reply with unexpected payload: \(message)")
    }

    // A reply to `phx_join` carries the join's ref. A late reply to an earlier join of this
    // topic matches neither the current join nor a push, so it is dropped.
    if ref == joinRef {
      didReceiveJoinReply(ref: ref, status: PushStatus(rawValue: status), payload: message.payload)
    } else {
      didReceiveReply(ref: ref, status: PushStatus(rawValue: status), payload: message.payload)
    }
  }

  private func didReceiveJoinReply(ref: String, status: PushStatus, payload: JSONObject) {
    let response = payload["response"]
    guard status != .error else {
      let reason =
        response?.objectValue?["reason"]?.stringValue
        ?? response?.stringValue
        ?? "The server rejected the join."
      didReceiveJoinError(.joinError(reason: reason), for: ref)
      return
    }

    guard status == .ok else { return }
    if let changes = response?.objectValue?[ChannelEvent.postgresChanges] {
      do {
        serverChanges = try changes.decode(as: [PostgresJoinConfig].self)
      } catch {
        didReceiveJoinError(.unreadableJoinReply(error), for: ref)
        return
      }
    }
    didReceiveSubscribedOK()
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

  /// Called by the client when a binary broadcast frame (type 0x04) is received.
  func handleBinaryBroadcast(_ broadcast: DecodedBroadcast) {
    let routed = route(broadcast, bindings: bindings)
    if routed.listeners.isEmpty, case .binary = broadcast.payload {
      logger.warning(
        "Received binary broadcast for event '\(broadcast.event)' but no Data stream is open. Open one with broadcastData(event:) to receive Data."
      )
    }
    deliver(routed)
  }

  private func deliver(_ routed: ChannelRoute) {
    for index in routed.listeners {
      listeners[index].listener.yield(routed.delivery)
    }
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

  var bindings: [ChannelBinding] {
    listeners.map(\.listener.binding)
  }

  /// The waits between join attempts after a timeout, a lost connection, or a transient join
  /// error. The last step repeats.
  static let rejoinBackoff = BackoffPolicy.steps([
    .seconds(1), .seconds(2), .seconds(5), .seconds(10),
  ])

  /// The wait before the next join attempt after the server applied a rate limit.
  static let rateLimitBackoff: Duration = .seconds(30)
}
