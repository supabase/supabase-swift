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

  /// Per-call fan-out table for `postgresChanges(for:)` streams (Task 28).
  /// Keyed by the per-stream consumer UUID (a fresh UUID minted per `postgresChanges(for:)` call).
  /// Each call registers a type-erased closure that decodes and yields the payload.
  var postgresConsumers: [UUID: @Sendable (PhoenixMessage) -> Void] = [:]

  /// Per-call fan-out table of closures called when the channel closes (postgres streams).
  /// Each `postgresChanges(for:)` call registers a closure that finishes its stream.
  var postgresFinishers: [UUID: @Sendable (CloseReason) -> Void] = [:]

  /// Per-call fan-out table of closures called when a system postgres_changes error arrives
  /// (Finding H6). Keyed by stream consumer UUID.
  var postgresErrorFinishers: [UUID: @Sendable (String) -> Void] = [:]

  /// Indirection map: registration UUID (from `ChangeRegistrationConfig.id`) → [consumer UUIDs].
  ///
  /// When `postgresChanges(for:)` is called, the consumer is registered in `postgresConsumers`
  /// keyed by a fresh consumer UUID. This map links a registration's stable UUID to the set of
  /// consumer UUIDs currently subscribed to it. `_routePostgresChange` uses
  /// `serverIDRouting[serverID]` → registration UUIDs → this map → consumer UUIDs → handlers.
  var registrationConsumers: [UUID: [UUID]] = [:]

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

  /// Routing map from server-assigned postgres subscription ID (integer, from the phx_reply
  /// `postgres_changes` array) to the set of client registration UUIDs that share that id.
  ///
  /// Built (or rebuilt) in `_performJoin` after each successful ok reply. The server assigns
  /// one integer id per entry in the join's `postgres_changes` array, in the same order.
  /// Multiple client registrations may share the same server id (identical subscriptions).
  /// An incoming `postgres_changes` frame with `ids:[0,2]` fans out to all UUIDs in those slots.
  var serverIDRouting: [Int: [UUID]] = [:]

  /// The joinRef assigned during the most recent successful (or in-progress) `subscribe()`.
  /// Stored so subsequent frames for this channel (which carry the joinRef) can be validated.
  private(set) var joinRef: String?

  /// In-flight join task — coalesces concurrent `subscribe()` callers (Decision 14h).
  private var joinTask: Task<Void, any Error>?

  // MARK: - Rejoin eligibility (Task 29)

  /// Tracks whether this channel should be automatically re-joined after a transport reconnect.
  ///
  /// Set to `true` when `subscribe()` completes successfully (channel transitions to `.joined`).
  /// Cleared to `false` when the user explicitly calls `leave()`.
  ///
  /// Channels that were transport-dropped (not user-left) and had `.joined` state are eligible
  /// for transparent re-join (Decision 6 / Decision 18).
  var shouldRejoin: Bool = false

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

  func removePostgresConsumer(id consumerID: UUID, registrationID: UUID? = nil) {
    postgresConsumers.removeValue(forKey: consumerID)
    postgresFinishers.removeValue(forKey: consumerID)
    postgresErrorFinishers.removeValue(forKey: consumerID)
    // Remove this consumer UUID from the registrationConsumers indirection map.
    if let regID = registrationID {
      registrationConsumers[regID]?.removeAll { $0 == consumerID }
      if registrationConsumers[regID]?.isEmpty == true {
        registrationConsumers.removeValue(forKey: regID)
      }
    }
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
      finishAllPostgresConsumers(reason: reason)
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
    log(.info, .channel, "Joining channel", metadata: ["topic": topic])
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
      // Build the server-id routing map from the join reply's postgres_changes array.
      // The server assigns integer ids in the same order as the client's postgres_changes
      // entries. Map each server id → set of client registration UUIDs.
      _buildServerIDRouting(from: reply.response)
      // Mark this channel as eligible for transparent re-join on reconnect (Task 29).
      shouldRejoin = true
      log(.info, .channel, "Channel joined", metadata: ["topic": topic])
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
      log(.warn, .channel, "Channel join rejected: \(reason)", metadata: ["topic": topic])
      transition(to: .closed(.unauthorized))
      throw RealtimeError.channelJoinRejected(reason: reason)
    }
  }

  // MARK: - Rejoin (Task 29)

  /// Re-sends `phx_join` after a transparent transport reconnect.
  ///
  /// Called exclusively from the `Realtime` reconnection loop after a successful reconnect.
  /// Unlike `subscribe()`, this method:
  /// - Does NOT check `shouldRejoin` — the caller is responsible for the eligibility check.
  /// - Does NOT guard on `.joined` idempotency (the channel may still appear `.joined`
  ///   from the previous connection's state, so we always re-send).
  /// - Does NOT terminate any open streams (Decision 6 — streams survive the transport gap).
  /// - Re-tracks presence if `isPresenceTracked` is true (Decision 18).
  ///
  /// On success, the channel remains / transitions to `.joined`.
  /// On failure (timeout or rejection), the channel transitions to `.closed(...)`.
  func rejoin() async {
    guard let realtime else {
      transition(to: .closed(.clientDisconnected))
      return
    }

    // Reset the joinTask so a concurrent subscribe() doesn't coalesce onto a stale task.
    joinTask = nil

    // Generate a fresh joinRef for this connection's join.
    let ref = realtime.nextRef()
    joinRef = ref

    // Transition to .joining. We call transition(to:) which emits to state observers.
    // .joining is not a terminal state so no finishers are invoked — streams stay open.
    transition(to: .joining)

    // Build the join payload.
    let accessToken: String?
    do {
      accessToken = try await realtime.accessTokenForJoin()
    } catch {
      // Auth failure: close the channel.
      transition(to: .closed(.unauthorized))
      return
    }

    let joinPayload = JoinPayload.make(
      from: options, accessToken: accessToken, registrations: pendingRegistrations
    )

    let payloadObject: JSONObject
    do {
      payloadObject = try joinPayload.toJSONObject()
    } catch {
      transition(to: .closed(.transportFailure))
      return
    }

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
      transition(to: .closed(.transportFailure))
      return
    }

    do {
      try await realtime.sendText(text)
    } catch {
      transition(to: .closed(.transportFailure))
      return
    }

    let joinTimeout = realtime.configuration.joinTimeout
    let reply: PushReply
    do {
      reply = try await realtime.awaitReply(
        ref: ref,
        timeout: joinTimeout,
        timeoutError: .channelJoinTimeout
      )
    } catch {
      transition(to: .closed(.transportFailure))
      return
    }

    if reply.status == "ok" {
      _buildServerIDRouting(from: reply.response)
      // shouldRejoin stays true — still eligible for future reconnects.
      transition(to: .joined)

      // Re-track presence if it was active before the disconnect (Decision 18).
      if isPresenceTracked, let payload = lastTrackedPresencePayload {
        await _retrackPresence(payload: payload, realtime: realtime)
      }
    } else {
      // Server rejected the rejoin (e.g. revoked auth). This is terminal: clear
      // `shouldRejoin` so the channel is NOT re-attempted on every subsequent
      // reconnect (which would loop indefinitely). The caller must explicitly
      // `subscribe()` again to re-establish. Transient transport failures above
      // intentionally keep `shouldRejoin` true so the next reconnect retries.
      shouldRejoin = false
      transition(to: .closed(.unauthorized))
    }
  }

  /// Re-sends a presence track frame using the last stored payload. Called after a successful
  /// rejoin when `isPresenceTracked` is true (Decision 18).
  ///
  /// Failures are swallowed — the presence state will be stale but the channel stays open.
  private func _retrackPresence(payload: JSONObject, realtime: Realtime) async {
    let ref = realtime.nextRef()
    let currentJoinRef = joinRef

    let text: String
    do {
      text = try realtime.serializer.encodeText(
        joinRef: currentJoinRef,
        ref: ref,
        topic: topic,
        event: PhoenixEvent.presence.rawValue,
        payload: payload
      )
    } catch {
      // Encoding failure — swallow; presence state is stale but channel is still open.
      return
    }

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

    do {
      try await realtime.sendText(text)
    } catch {
      replyTask.cancel()
      return
    }

    // Await the ACK best-effort; swallow failure.
    _ = try? await replyTask.value
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

    // Clear the rejoin flag: a user-initiated leave must NOT trigger transparent re-join (Task 29).
    shouldRejoin = false

    log(.info, .channel, "Leaving channel", metadata: ["topic": topic])
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
    log(.info, .channel, "Channel left", metadata: ["topic": topic])
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
    log(.debug, .presence, "Presence tracked", metadata: ["topic": topic])
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
    log(.debug, .presence, "Presence untracked", metadata: ["topic": topic])
    lastTrackedPresencePayload = nil
    isPresenceTracked = false
  }

  // MARK: - Frame router entry point

  /// Called by the frame router when a message arrives for this channel's topic.
  /// Fans the message out to all registered `messages()` consumers, all
  /// type-erased `broadcasts(of:event:)` consumers, presence consumers, and
  /// postgres_changes consumers (Task 28).
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
    // Postgres fan-out (Task 28).
    switch message.event {
    case .postgresChanges:
      _routePostgresChange(message)
    case .system:
      _routeSystemEvent(message)
    default:
      break
    }
  }

  // MARK: - Postgres routing (Task 28)

  /// Routes an incoming `postgres_changes` frame to all consumers whose registration id
  /// maps to one of the server ids listed in the frame's `ids` array.
  ///
  /// Wire shape: `{ "ids": [0, 2, ...], "data": { "type": "INSERT"|"UPDATE"|"DELETE",
  /// "record": {...}, "old_record": {...}, "columns": [...], "commit_timestamp": "..." } }`
  private func _routePostgresChange(_ message: PhoenixMessage) {
    guard case .json(let jsonValue) = message.payload,
      let obj = jsonValue.objectValue
    else { return }

    // Extract ids array.
    guard let idsValue = obj["ids"],
      let idsArray = idsValue.arrayValue
    else { return }

    let serverIDs: [Int] = idsArray.compactMap { $0.intValue }
    guard !serverIDs.isEmpty else { return }

    // Verify data object exists before dispatching; avoids handlers processing malformed frames.
    guard obj["data"]?.objectValue != nil else { return }

    // For each server id, find all mapped registration UUIDs, then all consumer UUIDs for
    // each registration, and dispatch to the corresponding handler.
    for serverID in serverIDs {
      guard let registrationUUIDs = serverIDRouting[serverID] else { continue }
      for registrationUUID in registrationUUIDs {
        guard let consumerUUIDs = registrationConsumers[registrationUUID] else { continue }
        for consumerUUID in consumerUUIDs {
          postgresConsumers[consumerUUID]?(message)
        }
      }
    }
  }

  /// Routes an incoming `system` event. If it signals a postgres_changes subscription
  /// failure (extension == "postgres_changes", status == "error"), all postgres streams
  /// are finished throwing `.postgresSubscriptionFailed(reason:)`.
  ///
  /// Design note: we fail ALL postgres streams because the system event does not include
  /// enough information to identify which specific subscription failed.
  private func _routeSystemEvent(_ message: PhoenixMessage) {
    guard case .json(let jsonValue) = message.payload,
      let obj = jsonValue.objectValue
    else { return }

    guard let ext = obj["extension"]?.stringValue, ext == "postgres_changes",
      let status = obj["status"]?.stringValue, status == "error"
    else { return }

    let reason = obj["message"]?.stringValue ?? "Unknown postgres subscription error"
    log(.error, .postgres, "Postgres subscription error: \(reason)", metadata: ["topic": topic])
    _failAllPostgresConsumers(reason: reason)
  }

  /// Builds the server-id routing map from the join reply's `postgres_changes` response array.
  ///
  /// The server returns an array of objects in the same order as the client's `postgres_changes`
  /// entries. Each object has an `id` integer key. Multiple entries may share the same integer id
  /// (identical subscriptions collapse). We map `serverID -> [registrationUUID]`.
  private func _buildServerIDRouting(from response: JSONValue) {
    var routing: [Int: [UUID]] = [:]
    guard let responseObj = response.objectValue,
      let changesArray = responseObj["postgres_changes"]?.arrayValue
    else {
      serverIDRouting = [:]
      return
    }

    // The changesArray indices correspond to pendingRegistrations indices.
    for (index, entry) in changesArray.enumerated() {
      guard let serverID = entry.objectValue?["id"]?.intValue,
        index < pendingRegistrations.count
      else { continue }
      let regUUID = pendingRegistrations[index].id
      if routing[serverID] == nil {
        routing[serverID] = [regUUID]
      } else {
        routing[serverID]?.append(regUUID)
      }
    }

    serverIDRouting = routing
  }

  // MARK: - Logging helper

  /// Emits a log event via the owning `Realtime` actor's logger.
  /// No-ops if the `Realtime` reference has been deallocated.
  private func log(
    _ level: LogLevel,
    _ category: Category,
    _ message: String,
    metadata: [String: String] = [:]
  ) {
    realtime?.log(level, category, message, metadata: metadata)
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

  /// Finishes all open `postgresChanges(for:)` streams by invoking each finisher closure.
  /// The finisher throws `.channelClosed(reason)` into the stream.
  private func finishAllPostgresConsumers(reason: CloseReason) {
    for finisher in postgresFinishers.values {
      finisher(reason)
    }
    postgresConsumers.removeAll()
    postgresFinishers.removeAll()
    postgresErrorFinishers.removeAll()
    registrationConsumers.removeAll()
  }

  /// Fails all postgres streams with `.postgresSubscriptionFailed(reason:)`.
  /// Used when a system event signals a postgres subscription error (Finding H6).
  private func _failAllPostgresConsumers(reason: String) {
    for finisher in postgresErrorFinishers.values {
      finisher(reason)
    }
    postgresConsumers.removeAll()
    postgresFinishers.removeAll()
    postgresErrorFinishers.removeAll()
    registrationConsumers.removeAll()
  }
}
