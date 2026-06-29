//
//  Channel.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation
import Helpers

/// A Realtime channel that represents a named topic on the server.
///
/// Obtain a `Channel` by calling `Realtime.channel(_:configure:)`. The channel's
/// `topic` and `options` are immutable after creation.
public actor Channel {
  /// The Phoenix topic this channel is subscribed to (e.g. `"realtime:public:messages"`).
  public nonisolated let topic: String

  /// The options applied at channel creation. Immutable after creation (Decision 33).
  public nonisolated let options: ChannelOptions

  /// Weak back-reference to the owning `Realtime` actor.
  ///
  /// **Cycle-break (Task 16):** `Realtime.channels` holds the `Channel` strongly.
  /// If `Channel` also held `Realtime` strongly, neither could ever deinit — which
  /// would defeat Task 32's leaked-channel `deinit` warning. Storing it weakly
  /// breaks the cycle. Future channel methods (Task 17+) will guard-unwrap this
  /// reference and throw `.channelClosed(...)` if `Realtime` has already been
  /// deallocated.
  weak var realtime: Realtime?

  // MARK: - Channel state

  /// The current channel state. Drives `state` stream emissions.
  /// Internal (not private) so Channel+Broadcast.swift (same module, separate file) can read it.
  var channelState: ChannelState = .unsubscribed

  /// Broadcast list of `state` stream continuations.
  /// Mirrors the pattern used by `Realtime.statusContinuations`.
  private var stateContinuations: [UUID: AsyncStream<ChannelState>.Continuation] = [:]

  /// Per-call fan-out table for `messages()` streams.
  /// Each `messages()` call registers a fresh continuation here; `receive(_:)` yields
  /// every incoming frame to all registered continuations.
  private var messagesContinuations: [UUID: AsyncStream<PhoenixMessage>.Continuation] = [:]

  /// Per-call fan-out table for `broadcasts(of:event:)` typed streams.
  /// Each call registers a type-erased closure that filters, decodes, and yields
  /// the message into its owning `AsyncThrowingStream` continuation.
  /// Closures are stored as `@Sendable (PhoenixMessage) -> Void` so the registry
  /// itself is type-erased; the concrete `T` is captured in the closure.
  var broadcastConsumers: [UUID: @Sendable (PhoenixMessage) -> Void] = [:]

  /// Per-call fan-out table of closures called when the channel closes.
  /// Each `broadcasts(of:event:)` call registers a closure that finishes its
  /// stream with the given `CloseReason`.
  var broadcastFinishers: [UUID: @Sendable (CloseReason) -> Void] = [:]

  /// Per-call fan-out table for `observe(_:)` and `diffs(_:)` presence streams.
  /// Each call registers a type-erased closure that decodes and yields the
  /// message into its owning `AsyncStream` continuation.
  /// Closures are stored as `@Sendable (PhoenixMessage) -> Void` so the registry
  /// itself is type-erased; the concrete `T` and per-consumer state are captured in the closure.
  var presenceConsumers: [UUID: @Sendable (PhoenixMessage) -> Void] = [:]

  /// Per-call fan-out table of closures called when the channel closes (presence streams).
  /// Each `observe`/`diffs` call registers a closure that finishes its `AsyncStream` cleanly.
  var presenceFinishers: [UUID: @Sendable () -> Void] = [:]

  // MARK: - Postgres change registrations (Task 27)

  /// Ordered list of pending postgres-changes registrations.
  ///
  /// Populated by the `inserts`/`updates`/`deletes`/`changes` factories in
  /// `Channel+Postgres.swift` before `subscribe()` is called. Each entry is
  /// baked into `config.postgres_changes` during `_performJoin`.
  ///
  /// **Reusability (Decision 14c):** registrations are NOT cleared on `leave()`;
  /// they persist and replay on the next `subscribe()`. New registrations may be
  /// added between `leave()` and resubscribe as long as the state is `.closed`.
  var pendingRegistrations: [ChangeRegistrationConfig] = []

  /// The joinRef assigned during the most recent successful (or in-progress) `subscribe()`.
  /// Stored so subsequent frames for this channel (which carry the joinRef) can be validated.
  private(set) var joinRef: String?

  /// In-flight join task — coalesces concurrent `subscribe()` callers (Decision 14h).
  private var joinTask: Task<Void, any Error>?

  // MARK: - Presence tracking state (Task 24)

  /// The last encoded presence state sent via `sendPresenceTrack`. Stored for re-track on
  /// reconnect (Task 25 consumes this to re-send presence after channel rejoin).
  var lastTrackedPresencePayload: JSONObject?

  /// Whether presence is currently being tracked on this channel. Set to `true` by
  /// `sendPresenceTrack` and `false` by `sendPresenceUntrack` / channel close.
  var isPresenceTracked: Bool = false

  // MARK: - Init

  init(topic: String, options: ChannelOptions, realtime: Realtime) {
    self.topic = topic
    self.options = options
    self.realtime = realtime
  }

  // MARK: - State stream

  /// Returns a fresh `AsyncStream<ChannelState>` seeded with the current state.
  ///
  /// Each call mints an independent stream. The seeded value is delivered
  /// synchronously before the caller's first `await it.next()`. The stream
  /// completes only when its task is cancelled.
  public var state: AsyncStream<ChannelState> {
    let id = UUID()
    let current = channelState
    let (stream, continuation) = AsyncStream<ChannelState>.makeStream()
    continuation.yield(current)
    stateContinuations[id] = continuation
    continuation.onTermination = { [weak self] _ in
      Task { [weak self] in await self?.removeStateContinuation(id: id) }
    }
    return stream
  }

  // MARK: - Messages feed

  /// Returns a fresh `AsyncStream<PhoenixMessage>` that receives every frame routed
  /// to this channel by the frame router.
  ///
  /// ## Per-call fan-out
  /// Each call mints an independent stream. All registered streams receive a copy of
  /// every frame delivered via `receive(_:)`. Streams created before `subscribe()` are
  /// valid — they start producing once frames arrive after the join.
  ///
  /// ## Termination
  /// The stream finishes automatically when `leave()` (or any terminal close) is called.
  /// Consumers' `for await` loops will end cleanly without an error.
  public func messages() -> AsyncStream<PhoenixMessage> {
    let id = UUID()
    let (stream, continuation) = AsyncStream<PhoenixMessage>.makeStream()
    messagesContinuations[id] = continuation
    continuation.onTermination = { [weak self] _ in
      Task { [weak self] in await self?.removeMessagesContinuation(id: id) }
    }
    return stream
  }

  // MARK: - Private helpers

  private func removeStateContinuation(id: UUID) {
    stateContinuations.removeValue(forKey: id)
  }

  private func removeMessagesContinuation(id: UUID) {
    messagesContinuations.removeValue(forKey: id)
  }

  func removeBroadcastConsumer(id: UUID) {
    broadcastConsumers.removeValue(forKey: id)
    broadcastFinishers.removeValue(forKey: id)
  }

  func removePresenceConsumer(id: UUID) {
    presenceConsumers.removeValue(forKey: id)
    presenceFinishers.removeValue(forKey: id)
  }

  /// Transitions the channel to `newState` and broadcasts to all state observers.
  /// When transitioning to a terminal `.closed` state, all `messages()` streams are
  /// finished so consumers' `for await` loops end cleanly.
  func transition(to newState: ChannelState) {
    channelState = newState
    for continuation in stateContinuations.values {
      continuation.yield(newState)
    }
    if case .closed(let reason) = newState {
      finishAllMessagesContinuations()
      finishAllBroadcastConsumers(reason: reason)
      finishAllPresenceConsumers()
    }
  }

  // MARK: - Subscribe

  /// Subscribes the channel to its topic on the server by performing the `phx_join` handshake.
  ///
  /// ## Idempotency + coalescing (Decision 14h)
  /// - Already `.joined`: returns immediately.
  /// - Join in flight: awaits the same in-flight task (concurrent callers coalesce).
  /// - `.unsubscribed` / `.closed`: sends a fresh `phx_join`.
  ///
  /// ## State machine
  /// `.unsubscribed`/`.closed` → `.joining` → `.joined` (on ok reply)
  ///                                         → throws `.channelJoinRejected` (on non-ok reply)
  ///                                         → throws `.channelJoinTimeout` (on timeout)
  ///
  /// - Throws: `RealtimeError.channelClosed` if the owning `Realtime` has been deallocated.
  /// - Throws: `RealtimeError.channelJoinTimeout` if no reply arrives within `joinTimeout`.
  /// - Throws: `RealtimeError.channelJoinRejected` if the server responds with a non-ok status.
  public func subscribe() async throws(RealtimeError) {
    // Guard: ensure the owning Realtime is still alive.
    guard let realtime else { throw .channelClosed(.clientDisconnected) }

    // Idempotent: already joined — no-op.
    if channelState == .joined { return }

    // Coalesce: if a join is already in flight, await that task.
    if let existing = joinTask {
      do {
        try await existing.value
      } catch let error as RealtimeError {
        throw error
      } catch {
        throw .channelJoinTimeout
      }
      return
    }

    // Kick off the join as an unstructured task so concurrent callers can coalesce.
    let task = Task<Void, any Error> {
      try await self._performJoin(realtime: realtime)
    }
    joinTask = task

    do {
      try await task.value
      joinTask = nil
    } catch let error as RealtimeError {
      joinTask = nil
      throw error
    } catch {
      joinTask = nil
      throw .channelJoinTimeout
    }
  }

  /// Performs the actual `phx_join` wire handshake. Called exclusively from `subscribe()`.
  private func _performJoin(realtime: Realtime) async throws(RealtimeError) {
    // Guard: only start a fresh join from a quiescent state.
    // (.joining / .leaving with no in-flight task should not happen given the
    // coalescing in subscribe(), but guard defensively to avoid duplicate
    // .joining emissions and state-machine confusion.)
    switch channelState {
    case .unsubscribed: break
    case .closed: break
    default: return
    }

    // Generate a joinRef (Phoenix uses ref == joinRef for the join push).
    // `nextRef()` is nonisolated — no actor hop needed.
    let ref = realtime.nextRef()
    joinRef = ref

    // Transition to .joining BEFORE awaiting the access token so the channel
    // reflects the correct state during the entire join handshake.
    transition(to: .joining)

    // Build the join payload, baking in any pending postgres-changes registrations.
    let accessToken = try await realtime.accessTokenForJoin()
    let joinPayload = JoinPayload.make(
      from: options, accessToken: accessToken, registrations: pendingRegistrations
    )

    let payloadObject: JSONObject
    do {
      payloadObject = try joinPayload.toJSONObject()
    } catch {
      throw .encoding(underlying: error)
    }

    // Encode the phx_join text frame. `serializer` is nonisolated — no actor hop needed.
    let text: String
    do {
      text = try realtime.serializer.encodeText(
        joinRef: ref,
        ref: ref,
        topic: topic,
        event: PhoenixEvent.join.rawValue,
        payload: payloadObject
      )
    } catch {
      throw error as? RealtimeError ?? .encoding(underlying: error)
    }

    // Lazy-connect + send. `sendText` calls `connect()` if not already connected.
    try await realtime.sendText(text)

    // Await the phx_reply. Read configuration via actor isolation.
    let joinTimeout = realtime.configuration.joinTimeout
    let reply = try await realtime.awaitReply(
      ref: ref,
      timeout: joinTimeout,
      timeoutError: .channelJoinTimeout
    )

    if reply.status == "ok" {
      transition(to: .joined)
    } else {
      // Extract a human-readable reason from the response if available.
      let reason: String
      if let obj = reply.response.objectValue,
        let r = obj["reason"]?.stringValue
      {
        reason = r
      } else {
        reason = "Server rejected the channel join (status: \(reply.status))."
      }
      transition(to: .closed(.unauthorized))
      throw RealtimeError.channelJoinRejected(reason: reason)
    }
  }

  // MARK: - Leave

  /// Unsubscribes the channel from its topic by performing the `phx_leave` handshake.
  ///
  /// ## State machine
  /// `.joined` → `.leaving` → `.closed(.userRequested)` (on ok reply)
  ///
  /// ## Idempotency
  /// If the channel is already `.closed` or `.unsubscribed`, this is a no-op.
  /// Calling `leave()` a second time on an already-closed channel returns immediately.
  ///
  /// ## In-flight join
  /// If a `subscribe()` join is currently in flight, `leave()` awaits its completion
  /// first (best-effort), then proceeds to leave. This ensures the join/leave handshake
  /// is always well-ordered on the server.
  ///
  /// ## Error semantics
  /// On transport failure or timeout the channel's local state is set to
  /// `.closed(.userRequested)` regardless — the local handle is torn down. The
  /// error is then rethrown so the caller can detect that the server may not have
  /// confirmed the leave.
  ///
  /// ## Re-subscribe
  /// After leave, the channel is `.closed(.userRequested)`. Calling `subscribe()`
  /// again from this state performs a fresh `phx_join` (the state machine guard in
  /// `subscribe()` already permits `.closed`).
  ///
  /// - Throws: `RealtimeError.channelJoinTimeout` if no reply arrives within `leaveTimeout`.
  public func leave() async throws(RealtimeError) {
    // If the owning Realtime is gone, there is nothing to leave.
    guard let realtime else {
      transition(to: .closed(.userRequested))
      return
    }

    // Idempotent: already closed/unsubscribed — no-op.
    switch channelState {
    case .closed, .unsubscribed:
      return
    default:
      break
    }

    // If a join is in flight, await it first so leave is well-ordered on the server.
    if let existing = joinTask {
      // Best-effort: ignore any join error; we are leaving regardless.
      try? await existing.value
      // After the join resolves the state is either .joined or .closed(rejected/timeout).
      // If it ended up closed, we are done — nothing to leave.
      switch channelState {
      case .closed, .unsubscribed:
        return
      default:
        break
      }
    }

    // Transition to .leaving to signal in-progress leave.
    transition(to: .leaving)

    // Generate a ref for the phx_leave push.
    let ref = realtime.nextRef()

    // Use the stored joinRef (set during subscribe). If somehow nil, use the ref as fallback.
    let currentJoinRef = joinRef ?? ref

    // Encode the phx_leave text frame.
    let text: String
    do {
      text = try realtime.serializer.encodeText(
        joinRef: currentJoinRef,
        ref: ref,
        topic: topic,
        event: PhoenixEvent.leave.rawValue,
        payload: [:]
      )
    } catch {
      // Encoding failed: close locally and rethrow.
      transition(to: .closed(.userRequested))
      joinRef = nil
      throw error as? RealtimeError ?? .encoding(underlying: error)
    }

    // Send the phx_leave frame. On transport failure, close locally and rethrow.
    do {
      try await realtime.sendText(text)
    } catch {
      transition(to: .closed(.userRequested))
      joinRef = nil
      throw error
    }

    // Await the phx_reply. On timeout, close locally and rethrow.
    // Phoenix replies to phx_leave with a phx_reply; awaiting that is sufficient.
    do {
      _ = try await realtime.awaitReply(
        ref: ref,
        timeout: realtime.configuration.leaveTimeout,
        timeoutError: .channelJoinTimeout
      )
    } catch {
      // Local teardown regardless of server confirmation failure.
      transition(to: .closed(.userRequested))
      joinRef = nil
      throw error
    }

    // Success: transition to closed and reset joinRef so a future subscribe() gets a fresh ref.
    transition(to: .closed(.userRequested))
    joinRef = nil
  }

  // MARK: - Token push

  /// Sends an `access_token` Phoenix event for this channel if it is currently `.joined`.
  ///
  /// Called by `Realtime.updateToken(_:)` for every channel in the registry.
  ///
  /// ## No-ACK (Finding I1)
  /// The backend does not reply to `access_token` events, so this method does NOT
  /// register the frame in the in-flight registry and does NOT await a reply.
  /// It returns immediately after queueing the send.
  ///
  /// ## Failure semantics
  /// If the channel is not `.joined` or has no `joinRef`, this is a no-op.
  /// Transport failures from `sendText` are swallowed — the token is already stored
  /// on the `Realtime` actor for the next reconnect/rejoin.
  func pushAccessToken(_ newToken: String) async {
    guard channelState == .joined, let currentJoinRef = joinRef, let realtime else {
      return
    }

    let ref = realtime.nextRef()
    let text: String
    do {
      text = try realtime.serializer.encodeText(
        joinRef: currentJoinRef,
        ref: ref,
        topic: topic,
        event: PhoenixEvent.accessToken.rawValue,
        payload: ["access_token": .string(newToken)]
      )
    } catch {
      // Encoding failure: swallow and return — token is already stored for future joins.
      return
    }

    // Best-effort send: swallow transport errors (token is stored for future joins).
    try? await realtime.sendText(text)
  }

  // MARK: - Presence seam (Task 24)

  /// Encodes and sends a presence track frame, then awaits the server ACK.
  ///
  /// ## State gating
  /// - `.unsubscribed` / `.joining` → throws `.notSubscribed`
  /// - `.leaving` / `.closed` → throws `.channelClosed(reason)`
  /// - `.joined` → encodes `state` as `{ "event": "track", "payload": <encodedState> }`,
  ///   sends as a `"presence"` channel event (text frame), and awaits the phx_reply.
  ///
  /// ## Stored state
  /// The encoded payload is stored in `lastTrackedPresencePayload` for re-track on
  /// reconnect (Task 25). `isPresenceTracked` is set to `true`.
  ///
  /// ## Ack timeout
  /// Uses `broadcastAckTimeout` — presence track semantics are analogous to an acked push.
  func sendPresenceTrack<T: Codable & Sendable>(_ state: T) async throws(RealtimeError) {
    guard let realtime else { throw .channelClosed(.clientDisconnected) }

    // State gating.
    switch channelState {
    case .joined:
      break
    case .unsubscribed, .joining:
      throw .notSubscribed
    case .leaving:
      throw .channelClosed(.userRequested)
    case .closed(let reason):
      throw .channelClosed(reason)
    }

    // Encode the user state to JSON.
    let encodedPayload: AnyJSON
    do {
      let data = try JSONEncoder().encode(state)
      encodedPayload = try JSONDecoder().decode(AnyJSON.self, from: data)
    } catch {
      throw .encoding(underlying: error)
    }

    // Build the presence track outer payload.
    let outerPayload: JSONObject = [
      "event": .string("track"),
      "payload": encodedPayload,
    ]

    // Generate a ref for ACK correlation.
    let ref = realtime.nextRef()
    let currentJoinRef = joinRef

    // Encode the text frame.
    let text: String
    do {
      text = try realtime.serializer.encodeText(
        joinRef: currentJoinRef,
        ref: ref,
        topic: topic,
        event: PhoenixEvent.presence.rawValue,
        payload: outerPayload
      )
    } catch {
      throw error as? RealtimeError ?? .encoding(underlying: error)
    }

    // Register ref with the in-flight registry BEFORE sending so early replies are not missed.
    // The registry buffers the reply if it arrives before we call awaitReply.
    // We do NOT use async let here because typed throws + async let has a known Swift 6.1
    // limitation where the awaited error is widened to `any Error`.
    let broadcastAckTimeout = realtime.configuration.broadcastAckTimeout
    let registry = realtime.inflightPushRegistry
    let clock = realtime.configuration.clock
    // Register the pending entry (non-async; just adds to the dictionary).
    // awaitReply registers the entry and suspends; send it first into the registry
    // by starting the await as a Task so the entry is buffered before we send.
    let replyTask = Task<PushReply, any Error> {
      try await registry.awaitReply(
        ref: ref,
        timeout: broadcastAckTimeout,
        clock: clock,
        timeoutError: RealtimeError.broadcastAckTimeout
      )
    }

    // Send the frame.
    do {
      try await realtime.sendText(text)
    } catch {
      replyTask.cancel()
      throw error
    }

    // Await the ACK.
    do {
      _ = try await replyTask.value
    } catch let error as RealtimeError {
      throw error
    } catch {
      throw .broadcastAckTimeout
    }

    // Store state for Task 25 re-track on reconnect.
    lastTrackedPresencePayload = outerPayload
    isPresenceTracked = true
  }

  /// Sends a presence untrack frame, awaits the server ACK, and clears tracked state.
  ///
  /// Idempotent: if `isPresenceTracked` is already `false`, returns immediately (no-op).
  func sendPresenceUntrack() async throws(RealtimeError) {
    // Idempotent guard.
    guard isPresenceTracked else { return }

    guard let realtime else { throw .channelClosed(.clientDisconnected) }

    // State gating: must be joined to untrack.
    switch channelState {
    case .joined:
      break
    case .unsubscribed, .joining:
      throw .notSubscribed
    case .leaving:
      throw .channelClosed(.userRequested)
    case .closed(let reason):
      throw .channelClosed(reason)
    }

    // Build the presence untrack outer payload.
    let outerPayload: JSONObject = [
      "event": .string("untrack")
    ]

    // Generate a ref for ACK correlation.
    let ref = realtime.nextRef()
    let currentJoinRef = joinRef

    // Encode the text frame.
    let text: String
    do {
      text = try realtime.serializer.encodeText(
        joinRef: currentJoinRef,
        ref: ref,
        topic: topic,
        event: PhoenixEvent.presence.rawValue,
        payload: outerPayload
      )
    } catch {
      throw error as? RealtimeError ?? .encoding(underlying: error)
    }

    // Register ref BEFORE sending (same pattern as sendPresenceTrack).
    let broadcastAckTimeout = realtime.configuration.broadcastAckTimeout
    let registry = realtime.inflightPushRegistry
    let clock = realtime.configuration.clock
    let replyTask = Task<PushReply, any Error> {
      try await registry.awaitReply(
        ref: ref,
        timeout: broadcastAckTimeout,
        clock: clock,
        timeoutError: RealtimeError.broadcastAckTimeout
      )
    }

    // Send the frame.
    do {
      try await realtime.sendText(text)
    } catch {
      replyTask.cancel()
      throw error
    }

    // Await the ACK.
    do {
      _ = try await replyTask.value
    } catch let error as RealtimeError {
      throw error
    } catch {
      throw .broadcastAckTimeout
    }

    // Clear tracked state.
    lastTrackedPresencePayload = nil
    isPresenceTracked = false
  }

  // MARK: - Frame router entry point

  /// Called by the frame router when a message arrives for this channel's topic.
  /// Fans the message out to all registered `messages()` consumers, all
  /// type-erased `broadcasts(of:event:)` consumers, and all presence consumers.
  func receive(_ message: PhoenixMessage) {
    for continuation in messagesContinuations.values {
      continuation.yield(message)
    }
    for handler in broadcastConsumers.values {
      handler(message)
    }
    for handler in presenceConsumers.values {
      handler(message)
    }
  }

  // MARK: - Messages stream teardown

  /// Finishes all open `messages()` continuations so consumers' `for await` loops end.
  /// Called from `leave()` and any terminal close transition.
  private func finishAllMessagesContinuations() {
    for continuation in messagesContinuations.values {
      continuation.finish()
    }
    messagesContinuations.removeAll()
  }

  /// Finishes all open `broadcasts(of:event:)` streams by invoking each finisher closure.
  /// The finisher throws `.channelClosed(reason)` into the stream so callers receive the error.
  private func finishAllBroadcastConsumers(reason: CloseReason) {
    for finisher in broadcastFinishers.values {
      finisher(reason)
    }
    broadcastConsumers.removeAll()
    broadcastFinishers.removeAll()
  }

  /// Finishes all open presence `observe`/`diffs` streams cleanly (no throw — non-throwing streams).
  private func finishAllPresenceConsumers() {
    for finisher in presenceFinishers.values {
      finisher()
    }
    presenceConsumers.removeAll()
    presenceFinishers.removeAll()
  }
}
