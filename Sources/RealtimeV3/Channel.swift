//
//  Channel.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation
import Helpers

/// An item delivered by a channel's internal event feed (`_subscribeEvents()`).
///
/// Every per-call stream (`messages()`, `broadcasts`, presence, postgres) is a
/// transform over this feed. `.message` carries a routed frame; `.terminated`
/// carries the close reason once, immediately before the feed finishes, so a
/// throwing stream can finish with `.channelClosed(reason)` without racing a read
/// of `channelState`.
enum ChannelEvent: Sendable {
  case message(PhoenixMessage)
  case terminated(CloseReason)
}

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

  /// The single fan-out table backing every per-call stream on this channel.
  ///
  /// `messages()`, `broadcasts(of:event:)`, `presence.observe`/`diffs`, and
  /// `postgresChanges(for:)` are all transforms over a fresh subscription to this
  /// feed (see `_subscribeEvents()`): each filters and decodes the frames it cares
  /// about. `receive(_:)` yields `.message(_)` to every subscriber; a terminal close
  /// yields `.terminated(reason)` and then finishes them.
  ///
  /// Carrying the close reason in-band lets throwing streams finish with
  /// `.channelClosed(reason)` race-free, without reading `channelState` after the loop.
  /// Internal (not private) so `receive(_:)` in `Channel+Routing.swift` can fan out to it.
  var eventContinuations: [UUID: AsyncStream<ChannelEvent>.Continuation] = [:]

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

  /// Whether presence is currently being tracked on this channel. Set to `true` by
  /// `sendPresenceTrack` and `false` by `sendPresenceUntrack`; used to make untrack
  /// idempotent.
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
    _makeStream(initialState: ()) { _, message, continuation in
      continuation.yield(message)
    }
  }

  // MARK: - Event feed (internal)

  /// Registers a fresh subscriber to this channel's event feed and returns its stream.
  ///
  /// Every per-call stream is built on top of this. The returned stream yields
  /// `.message(_)` for each routed frame and a final `.terminated(reason)` when the
  /// channel closes. If the channel is already `.closed`, the stream is seeded with the
  /// terminal event immediately so late subscribers don't hang.
  ///
  /// The subscription removes itself from the fan-out table when the returned stream is
  /// finished or its consumer is cancelled (via `onTermination`).
  func _subscribeEvents() -> AsyncStream<ChannelEvent> {
    let (stream, continuation) = AsyncStream<ChannelEvent>.makeStream()

    // Late subscriber after a terminal close: deliver the reason and finish immediately.
    if case .closed(let reason) = channelState {
      continuation.yield(.terminated(reason))
      continuation.finish()
      return stream
    }

    let id = UUID()
    eventContinuations[id] = continuation
    continuation.onTermination = { [weak self] _ in
      Task { [weak self] in await self?.removeEventContinuation(id: id) }
    }
    return stream
  }

  // MARK: - Stream-transform helpers (internal)
  //
  // Every per-call stream is a transform over a fresh `_subscribeEvents()` subscription.
  // These two helpers centralize the boilerplate that would otherwise repeat in each
  // factory: subscribing on-actor, draining the feed in a task, finishing the output on
  // terminal close, and cancelling the task when the consumer goes away.
  //
  // The `body` only ever sees `.message` frames — the `.terminated` event is handled
  // here (clean finish for non-throwing streams, `.channelClosed(reason)` for throwing
  // streams). `State` is a per-subscription value threaded `inout` through every call so
  // stateful transforms (presence's running roster) need no external storage or lock.

  /// Builds a non-throwing `AsyncStream<T>` transform over the channel event feed.
  ///
  /// `body` is invoked for each `.message` frame with the running `state` and the output
  /// continuation; it may yield zero or more values. The stream finishes cleanly when the
  /// channel closes. Pass `initialState: ()` for stateless transforms.
  func _makeStream<T: Sendable, State: Sendable>(
    initialState: State,
    _ body: @escaping @Sendable (inout State, PhoenixMessage, AsyncStream<T>.Continuation) -> Void
  ) -> AsyncStream<T> {
    let base = _subscribeEvents()
    return AsyncStream<T> { continuation in
      let task = Task {
        var state = initialState
        for await event in base {
          switch event {
          case .terminated:
            continuation.finish()
            return
          case .message(let message):
            body(&state, message, continuation)
          }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Builds an `AsyncThrowingStream<T, any Error>` transform over the channel event feed.
  ///
  /// `body` is invoked (with `await`) for each `.message` frame; it may yield values or
  /// `throw` to terminate the stream (e.g. a decode failure or a postgres subscription
  /// error). A terminal channel close finishes the stream throwing
  /// `RealtimeError.channelClosed(reason)`. Pass `initialState: ()` for stateless transforms.
  func _makeThrowingStream<T: Sendable, State: Sendable>(
    initialState: State,
    _ body:
      @escaping @Sendable (
        inout State, PhoenixMessage, AsyncThrowingStream<T, any Error>.Continuation
      ) async throws -> Void
  ) -> AsyncThrowingStream<T, any Error> {
    let base = _subscribeEvents()
    return AsyncThrowingStream<T, any Error> { continuation in
      let task = Task {
        var state = initialState
        do {
          for await event in base {
            switch event {
            case .terminated(let reason):
              throw RealtimeError.channelClosed(reason)
            case .message(let message):
              try await body(&state, message, continuation)
            }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  // MARK: - Private helpers

  private func removeStateContinuation(id: UUID) {
    stateContinuations.removeValue(forKey: id)
  }

  private func removeEventContinuation(id: UUID) {
    eventContinuations.removeValue(forKey: id)
  }

  /// Transitions the channel to `newState` and broadcasts to all state observers.
  /// When transitioning to a terminal `.closed` state, all `messages()` streams are
  /// finished so consumers' `for await` loops end cleanly.
  ///
  /// ## Joined-topic registry (Task 32)
  /// - On `.joined`: adds `topic` to `Realtime.joinedTopics` via the nonisolated `_markJoined`.
  /// - On `.closed`: removes `topic` from `Realtime.joinedTopics` via `_markLeft`.
  ///   This fires for every close reason (userRequested, unauthorized, transportFailure, etc.)
  ///   so the deinit warning only fires for channels that are still in `.joined` state.
  func transition(to newState: ChannelState) {
    channelState = newState
    for continuation in stateContinuations.values {
      continuation.yield(newState)
    }

    // Update the nonisolated joinedTopics registry on the owning Realtime actor.
    // Both _markJoined and _markLeft are nonisolated on Realtime, so no await is needed.
    switch newState {
    case .joined:
      realtime?._markJoined(topic)
    case .closed:
      realtime?._markLeft(topic)
    default:
      break
    }

    if case .closed(let reason) = newState {
      // Deliver the close reason in-band to every subscriber, then finish the feed.
      // Each transform decides what this means for its stream: messages()/presence
      // finish cleanly, broadcasts()/postgres finish throwing `.channelClosed(reason)`.
      for continuation in eventContinuations.values {
        continuation.yield(.terminated(reason))
        continuation.finish()
      }
      eventContinuations.removeAll()
    }
  }

  // MARK: - Outgoing push (internal)

  /// Encodes and sends a single Phoenix frame for this channel, optionally awaiting its
  /// `phx_reply`.
  ///
  /// Thin wrapper over ``Realtime/_push(topic:_:_:ref:joinRef:lazyConnect:ack:)`` that
  /// supplies this channel's `topic` and defaults `joinRef` to the channel's current
  /// `joinRef`. All send paths (broadcast, presence, join, leave, access_token) funnel
  /// through here.
  ///
  /// - Parameters:
  ///   - event: The Phoenix event for the frame.
  ///   - body: The wire payload (text JSON, or a binary broadcast frame).
  ///   - ref: The push ref. Defaults to a fresh ref; `join` passes its own so `ref == joinRef`.
  ///   - joinRef: The join ref stamped on the frame. Defaults to the channel's current `joinRef`.
  ///   - ack: Whether to await a reply.
  /// - Returns: The `phx_reply` when `ack == .require`, otherwise `nil`.
  @discardableResult
  func _push(
    _ event: PhoenixEvent,
    _ body: PushBody,
    ref: String? = nil,
    joinRef: String? = nil,
    ack: AckPolicy = .none
  ) async throws(RealtimeError) -> PushReply? {
    guard let realtime else { throw .channelClosed(.clientDisconnected) }
    return try await realtime._push(
      topic: topic, event, body, ref: ref, joinRef: joinRef ?? self.joinRef, ack: ack)
  }

  /// Gates a send on the channel being `.joined`, mapping other states to the
  /// appropriate error: `.notSubscribed` while pre-join, `.channelClosed(reason)` once
  /// leaving or closed.
  func _requireJoinedForSend() throws(RealtimeError) {
    switch channelState {
    case .joined:
      return
    case .unsubscribed, .joining:
      throw .notSubscribed
    case .leaving:
      throw .channelClosed(.userRequested)
    case .closed(let reason):
      throw .channelClosed(reason)
    }
  }

  /// Encodes an `Encodable` value to `AnyJSON` using the configured encoder, mapping any
  /// failure to `.encoding`. Used to embed user payloads in broadcast/presence frames.
  /// Thin wrapper over ``Realtime/_encodeToJSON(_:)``.
  func _encodeToJSON<T: Encodable & Sendable>(_ value: T) throws(RealtimeError) -> AnyJSON {
    guard let realtime else { throw .channelClosed(.clientDisconnected) }
    return try realtime._encodeToJSON(value)
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
  ///
  /// Failures throw (and leave the channel in `.joining` for the transport/timeout cases, so the
  /// caller may retry); a server rejection transitions to `.closed(.unauthorized)` and throws
  /// `.channelJoinRejected`.
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

    switch try await _sendJoin(ref: ref, realtime: realtime) {
    case .joined:
      log(.info, .channel, "Channel joined", metadata: ["topic": topic])
      transition(to: .joined)
    case .rejected(let reason):
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

    do {
      switch try await _sendJoin(ref: ref, realtime: realtime) {
      case .joined:
        // shouldRejoin stays true — still eligible for future reconnects.
        transition(to: .joined)
      case .rejected:
        // Server rejected the rejoin (e.g. revoked auth). This is terminal: clear
        // `shouldRejoin` so the channel is NOT re-attempted on every subsequent reconnect
        // (which would loop indefinitely). The caller must explicitly `subscribe()` again.
        shouldRejoin = false
        transition(to: .closed(.unauthorized))
      }
    } catch {
      // Wire failure. An auth failure is treated as `.unauthorized`; transport/timeout/encode
      // are recoverable drops — `shouldRejoin` stays true so the next reconnect retries.
      if case .authenticationFailed = error {
        transition(to: .closed(.unauthorized))
      } else {
        transition(to: .closed(.transportFailure))
      }
    }
  }

  // MARK: - Join wire handshake (shared)

  /// The outcome of a `phx_join` reply: the server accepted the join, or rejected it.
  private enum JoinOutcome: Sendable {
    case joined
    case rejected(reason: String)
  }

  /// Shared `phx_join` wire handshake used by both `subscribe()` (`_performJoin`) and `rejoin()`.
  ///
  /// Assumes the channel is already `.joining` with `joinRef == ref`. Builds the join payload
  /// (baking in any pending postgres registrations), sends it, and awaits the reply. On an `ok`
  /// reply it builds the server-id routing map, marks the channel rejoin-eligible, and — when the
  /// join carried registrations — waits for the postgres `system` confirmation before returning
  /// `.joined`. A non-ok reply returns `.rejected`.
  ///
  /// Throws on any wire failure (auth, encode, transport, timeout, postgres subscription error).
  /// Performs no terminal state transition itself — each caller maps the outcome (and any thrown
  /// error) to its own state-machine policy.
  private func _sendJoin(ref: String, realtime: Realtime) async throws(RealtimeError) -> JoinOutcome
  {
    // If this join carries postgres_changes registrations, the server activates replication
    // asynchronously and confirms via a `system` event — the phx_reply alone is premature
    // (early changes would be missed). Subscribe to the event feed *before* sending the join so
    // that confirmation cannot be missed.
    let postgresEvents: AsyncStream<ChannelEvent>? =
      pendingRegistrations.isEmpty ? nil : _subscribeEvents()

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

    // Encode + send the phx_join (ref == joinRef) and await the reply.
    let reply = try await _push(
      .join, .text(payloadObject), ref: ref, joinRef: ref,
      ack: .require(timeout: realtime.configuration.joinTimeout, error: .channelJoinTimeout)
    )!

    guard reply.status == "ok" else {
      let reason =
        reply.response.objectValue?["reason"]?.stringValue
        ?? "Server rejected the channel join (status: \(reply.status))."
      return .rejected(reason: reason)
    }

    // Build the server-id routing map from the join reply's postgres_changes array (the server
    // assigns integer ids in the same order as the client's entries). Mark rejoin-eligible
    // BEFORE the (possibly slow) postgres wait so a confirmation failure still leaves the channel
    // eligible for a future reconnect.
    _buildServerIDRouting(from: reply.response)
    shouldRejoin = true

    if let postgresEvents {
      try await _awaitPostgresSubscribed(
        postgresEvents,
        timeout: realtime.configuration.joinTimeout,
        clock: realtime.configuration.clock
      )
    }
    return .joined
  }

  // MARK: - Postgres subscription confirmation

  /// Awaits the server's `system` confirmation that this channel's `postgres_changes`
  /// subscription is live, racing against `timeout`.
  ///
  /// A join whose payload carried registrations is only really subscribed once the server
  /// finishes setting up replication and emits a `system` event
  /// (`extension == "postgres_changes"`): `status == "ok"` succeeds, `status == "error"`
  /// throws `.postgresSubscriptionFailed`. The phx_reply arrives earlier and merely echoes
  /// the requested subscriptions, so relying on it alone drops the first changes.
  ///
  /// `events` must be a feed subscription created *before* the join was sent, so the
  /// confirmation cannot arrive in the gap before we start listening.
  private func _awaitPostgresSubscribed(
    _ events: AsyncStream<ChannelEvent>,
    timeout: Duration,
    clock: any Clock<Duration> & Sendable
  ) async throws(RealtimeError) {
    let outcome: Result<Void, RealtimeError> = await withTaskGroup(
      of: Result<Void, RealtimeError>.self
    ) { group in
      group.addTask {
        for await event in events {
          switch event {
          case .terminated(let reason):
            return .failure(.channelClosed(reason))
          case .message(let message):
            guard let system = SystemEventPayload(message), system.isPostgresChanges
            else { continue }
            switch system.status {
            case "ok":
              return .success(())
            case "error":
              return .failure(
                .postgresSubscriptionFailed(
                  reason: system.message ?? "postgres_changes subscription failed"))
            default:
              continue
            }
          }
        }
        // Feed ended before confirmation (channel deallocated) — treat as a join timeout.
        return .failure(.channelJoinTimeout)
      }
      group.addTask {
        try? await clock.sleep(for: timeout)
        return .failure(.channelJoinTimeout)
      }
      let first = await group.next() ?? .failure(.channelJoinTimeout)
      group.cancelAll()
      return first
    }

    switch outcome {
    case .success:
      return
    case .failure(let error):
      throw error
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

    // Clear the rejoin flag: a user-initiated leave must NOT trigger transparent re-join (Task 29).
    shouldRejoin = false

    log(.info, .channel, "Leaving channel", metadata: ["topic": topic])
    // Transition to .leaving to signal in-progress leave.
    transition(to: .leaving)

    // Encode + send the phx_leave frame and await its reply. On any failure (encode,
    // transport, or timeout) tear down locally and rethrow so the caller knows the server
    // may not have confirmed.
    do {
      _ = try await _push(
        .leave, .text([:]),
        ack: .require(timeout: realtime.configuration.leaveTimeout, error: .channelJoinTimeout)
      )
    } catch {
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
    guard channelState == .joined, joinRef != nil else { return }

    // Best-effort, no ACK (the backend does not reply to access_token): swallow encode and
    // transport errors — the token is already stored on Realtime for future joins.
    _ = try? await _push(
      .accessToken, .text(["access_token": .string(newToken)]), ack: .none)
  }

  // MARK: - Logging helper

  /// Emits a log event via the owning `Realtime` actor's logger.
  /// No-ops if the `Realtime` reference has been deallocated.
  /// Internal (not private) so the same-module extension files can log.
  func log(
    _ level: LogLevel,
    _ category: Category,
    _ message: String,
    metadata: [String: String] = [:]
  ) {
    realtime?.log(level, category, message, metadata: metadata)
  }

}
