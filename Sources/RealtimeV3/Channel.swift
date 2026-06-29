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

/// The wire form of an outgoing channel push, consumed by `Channel._push`.
///
/// `text` is a JSON text frame (join, leave, presence, access_token); the two
/// `broadcast*` cases are Phoenix binary broadcast frames (kind `0x03`) carrying
/// either a JSON envelope or raw bytes.
enum PushBody: Sendable {
  case text(JSONObject)
  case broadcastJSON(JSONObject)
  case broadcastData(Data)
}

/// Whether an outgoing push awaits a `phx_reply`.
///
/// `require` suspends until the matching reply arrives or `timeout` elapses, throwing
/// `error` on timeout. Best-effort sends (e.g. access_token) use `none` and/or a
/// `try?` at the call site.
enum AckPolicy: Sendable {
  case none
  case require(timeout: Duration, error: RealtimeError)
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
  private var eventContinuations: [UUID: AsyncStream<ChannelEvent>.Continuation] = [:]

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
  /// Centralizes the wire mechanics shared by every send path: ref generation, text/binary
  /// encoding (mapping encode failures to `.encoding`), lazy-connect send, and — when
  /// `ack == .require` — reply correlation via the in-flight registry. Send failures
  /// (`.transportFailure`/`.disconnected`) propagate unchanged.
  ///
  /// Because the registry buffers early replies, awaiting *after* sending is race-free, so
  /// every ack site uses this one flow (no manual pre-register task needed).
  ///
  /// - Parameters:
  ///   - event: The Phoenix event for the frame.
  ///   - body: The wire payload (text JSON, or a binary broadcast frame).
  ///   - ref: The push ref. Defaults to a fresh `nextRef()`; `join` passes its own ref so
  ///     `ref == joinRef`.
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
    let ref = ref ?? realtime.nextRef()
    let jr = joinRef ?? self.joinRef
    let serializer = realtime.serializer

    do {
      switch body {
      case .text(let payload):
        let text = try serializer.encodeText(
          joinRef: jr, ref: ref, topic: topic, event: event.rawValue, payload: payload)
        try await realtime.sendText(text)
      case .broadcastJSON(let payload):
        let data = try serializer.encodeBroadcastPush(
          joinRef: jr, ref: ref, topic: topic, event: event.rawValue, jsonPayload: payload)
        try await realtime.sendBinary(data)
      case .broadcastData(let payload):
        let data = try serializer.encodeBroadcastPush(
          joinRef: jr, ref: ref, topic: topic, event: event.rawValue, binaryPayload: payload)
        try await realtime.sendBinary(data)
      }
    } catch let error as RealtimeError {
      // Send-side failures (transport/disconnect) propagate unchanged.
      throw error
    } catch {
      // Encode failures map to `.encoding`.
      throw .encoding(underlying: error)
    }

    switch ack {
    case .none:
      return nil
    case .require(let timeout, let error):
      return try await realtime.awaitReply(ref: ref, timeout: timeout, timeoutError: error)
    }
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
  func _encodeToJSON<T: Encodable & Sendable>(_ value: T) throws(RealtimeError) -> AnyJSON {
    guard let realtime else { throw .channelClosed(.clientDisconnected) }
    do {
      let data = try realtime.configuration.encoder.encode(value)
      return try JSONDecoder().decode(AnyJSON.self, from: data)
    } catch {
      throw .encoding(underlying: error)
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

    // Encode + send the phx_join (ref == joinRef) and await the reply.
    let reply = try await _push(
      .join, .text(payloadObject), ref: ref, joinRef: ref,
      ack: .require(timeout: realtime.configuration.joinTimeout, error: .channelJoinTimeout)
    )!

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

    // Encode + send the phx_join (ref == joinRef) and await the reply. Encode, transport,
    // and timeout failures are all treated as a recoverable transport drop here.
    let reply: PushReply
    do {
      reply = try await _push(
        .join, .text(payloadObject), ref: ref, joinRef: ref,
        ack: .require(timeout: realtime.configuration.joinTimeout, error: .channelJoinTimeout)
      )!
    } catch {
      transition(to: .closed(.transportFailure))
      return
    }

    if reply.status == "ok" {
      _buildServerIDRouting(from: reply.response)
      // shouldRejoin stays true — still eligible for future reconnects.
      transition(to: .joined)
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

  // MARK: - Presence seam (Task 24)

  /// Encodes and sends a presence track frame, then awaits the server ACK.
  ///
  /// ## State gating
  /// - `.unsubscribed` / `.joining` → throws `.notSubscribed`
  /// - `.leaving` / `.closed` → throws `.channelClosed(reason)`
  /// - `.joined` → encodes `state` as `{ "event": "track", "payload": <encodedState> }`,
  ///   sends as a `"presence"` channel event (text frame), and awaits the phx_reply.
  ///
  /// ## Tracked flag
  /// `isPresenceTracked` is set to `true` so a later `untrack` is not a no-op.
  ///
  /// ## Ack timeout
  /// Uses `broadcastAckTimeout` — presence track semantics are analogous to an acked push.
  func sendPresenceTrack<T: Codable & Sendable>(_ state: T) async throws(RealtimeError) {
    guard let realtime else { throw .channelClosed(.clientDisconnected) }
    try _requireJoinedForSend()

    // Build the presence track outer payload (user state encoded via Configuration.encoder).
    let outerPayload: JSONObject = [
      "event": .string("track"),
      "payload": try _encodeToJSON(state),
    ]

    // Send and await the server ACK.
    _ = try await _push(
      .presence, .text(outerPayload),
      ack: .require(
        timeout: realtime.configuration.broadcastAckTimeout, error: .broadcastAckTimeout)
    )

    log(.debug, .presence, "Presence tracked", metadata: ["topic": topic])
    isPresenceTracked = true
  }

  /// Sends a presence untrack frame, awaits the server ACK, and clears tracked state.
  ///
  /// Idempotent: if `isPresenceTracked` is already `false`, returns immediately (no-op).
  func sendPresenceUntrack() async throws(RealtimeError) {
    // Idempotent guard.
    guard isPresenceTracked else { return }

    guard let realtime else { throw .channelClosed(.clientDisconnected) }
    try _requireJoinedForSend()

    // Send the presence untrack frame and await the server ACK.
    _ = try await _push(
      .presence, .text(["event": .string("untrack")]),
      ack: .require(
        timeout: realtime.configuration.broadcastAckTimeout, error: .broadcastAckTimeout)
    )

    // Clear tracked state.
    log(.debug, .presence, "Presence untracked", metadata: ["topic": topic])
    isPresenceTracked = false
  }

  // MARK: - Frame router entry point

  /// Called by the frame router when a message arrives for this channel's topic.
  ///
  /// Yields the frame to every event-feed subscriber; each per-call stream
  /// (`messages()`, `broadcasts`, presence, postgres) filters and decodes from there.
  ///
  /// Also handles server-initiated terminal events (`phx_close`, `phx_error`,
  /// and non-postgres `system` error frames) by transitioning to the appropriate
  /// `.closed` state. These routes guard on the current channel state so that a
  /// trailing `phx_close` from the server after our own `leave()` does NOT
  /// overwrite the already-set `.closed(.userRequested)` reason (idempotent).
  func receive(_ message: PhoenixMessage) {
    for continuation in eventContinuations.values {
      continuation.yield(.message(message))
    }
    // Channel-level reactions. `postgres_changes` frames and `system`
    // postgres-subscription errors are handled by the postgres transforms
    // themselves (they self-filter the feed), so they are not routed here.
    switch message.event {
    case .system:
      _routeSystemEvent(message)
    case .close:
      _handleServerClose(message)
    case .error:
      _handleServerError(message)
    default:
      break
    }
  }

  // MARK: - Server-initiated terminal event handlers

  /// Handles an unsolicited `phx_close` frame from the server.
  ///
  /// If the channel is already `.closed` (e.g. from our own `leave()`) or `.leaving`
  /// (our own leave is in progress), the frame is ignored so we never overwrite a
  /// user-requested close reason. Only unsolicited closes trigger a state transition.
  private func _handleServerClose(_ message: PhoenixMessage) {
    // Idempotency guard: ignore if already terminal or our own leave is in progress.
    switch channelState {
    case .closed, .leaving:
      return
    default:
      break
    }

    // Extract an optional message from the payload.
    let closeMessage: String?
    if case .json(let jsonValue) = message.payload,
      let obj = jsonValue.objectValue
    {
      closeMessage = obj["message"]?.stringValue
    } else {
      closeMessage = nil
    }

    log(
      .warn, .channel,
      "Server closed channel: \(closeMessage ?? "(no message)")",
      metadata: ["topic": topic]
    )

    // Clear shouldRejoin — a server-closed channel must not be auto-rejoined.
    shouldRejoin = false
    transition(to: .closed(.serverClosed(code: nil, message: closeMessage)))
  }

  /// Handles a `phx_error` frame from the server.
  ///
  /// Same idempotency guard as `_handleServerClose`: ignored when already terminal.
  private func _handleServerError(_ message: PhoenixMessage) {
    switch channelState {
    case .closed, .leaving:
      return
    default:
      break
    }

    let reason: String?
    if case .json(let jsonValue) = message.payload,
      let obj = jsonValue.objectValue
    {
      reason = obj["reason"]?.stringValue ?? obj["message"]?.stringValue
    } else {
      reason = nil
    }

    log(
      .error, .channel,
      "Server sent phx_error: \(reason ?? "(no reason)")",
      metadata: ["topic": topic]
    )

    shouldRejoin = false
    transition(to: .closed(.serverClosed(code: nil, message: reason)))
  }

  // MARK: - Postgres routing (Task 28)

  /// Returns the set of server-assigned subscription ids currently mapped to the given
  /// client registration UUID.
  ///
  /// Built from `serverIDRouting`, which is (re)built on every successful join/rejoin.
  /// A `postgresChanges(for:)` transform reads this live (per frame) to decide whether an
  /// incoming `postgres_changes` frame's `ids` array targets its registration.
  func postgresServerIDs(for registrationID: UUID) -> Set<Int> {
    var ids: Set<Int> = []
    for (serverID, registrationUUIDs) in serverIDRouting
    where registrationUUIDs.contains(registrationID) {
      ids.insert(serverID)
    }
    return ids
  }

  /// Routes an incoming `system` event.
  ///
  /// - If `extension == "postgres_changes"` and `status == "error"`: ignored here — the
  ///   postgres transforms self-filter this frame off the event feed and finish their own
  ///   streams with `.postgresSubscriptionFailed(reason:)`. The channel stays open.
  /// - Otherwise, if `status == "error"` and the message indicates an auth/token failure:
  ///   transitions the channel to `.closed(.unauthorized)` (server-initiated auth failure).
  /// - Otherwise, if `status == "error"` for any other reason:
  ///   transitions to `.closed(.serverClosed(code:message:))`.
  ///
  /// The channel-close path guards on the current state so it is idempotent when the
  /// channel is already `.closed` or `.leaving`.
  private func _routeSystemEvent(_ message: PhoenixMessage) {
    guard case .json(let jsonValue) = message.payload,
      let obj = jsonValue.objectValue
    else { return }

    let ext = obj["extension"]?.stringValue
    let status = obj["status"]?.stringValue
    let msgText = obj["message"]?.stringValue

    // postgres_changes subscription error → handled by the postgres transforms; channel stays open.
    if ext == "postgres_changes", status == "error" {
      let reason = msgText ?? "Unknown postgres subscription error"
      log(.error, .postgres, "Postgres subscription error: \(reason)", metadata: ["topic": topic])
      return
    }

    // Non-postgres system error → close the whole channel.
    guard status == "error" else { return }

    // Idempotency guard: if already terminal/leaving, do nothing.
    switch channelState {
    case .closed, .leaving:
      return
    default:
      break
    }

    let reason = msgText ?? "Unknown system error"
    log(.error, .channel, "System error: \(reason)", metadata: ["topic": topic])

    // Detect auth/token failures by looking for common keywords in the message.
    let lowerReason = reason.lowercased()
    let isAuthError =
      lowerReason.contains("token")
      || lowerReason.contains("auth")
      || lowerReason.contains("unauthorized")
      || lowerReason.contains("unauthenticated")
      || lowerReason.contains("forbidden")
      || lowerReason.contains("jwt")

    shouldRejoin = false
    if isAuthError {
      transition(to: .closed(.unauthorized))
    } else {
      transition(to: .closed(.serverClosed(code: nil, message: msgText)))
    }
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

}
