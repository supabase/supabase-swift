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
  private var channelState: ChannelState = .unsubscribed

  /// Broadcast list of `state` stream continuations.
  /// Mirrors the pattern used by `Realtime.statusContinuations`.
  private var stateContinuations: [UUID: AsyncStream<ChannelState>.Continuation] = [:]

  /// The joinRef assigned during the most recent successful (or in-progress) `subscribe()`.
  /// Stored so subsequent frames for this channel (which carry the joinRef) can be validated.
  private(set) var joinRef: String?

  /// In-flight join task — coalesces concurrent `subscribe()` callers (Decision 14h).
  private var joinTask: Task<Void, any Error>?

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

  // MARK: - Private helpers

  private func removeStateContinuation(id: UUID) {
    stateContinuations.removeValue(forKey: id)
  }

  /// Transitions the channel to `newState` and broadcasts to all state observers.
  func transition(to newState: ChannelState) {
    channelState = newState
    for continuation in stateContinuations.values {
      continuation.yield(newState)
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
    // Generate a joinRef (Phoenix uses ref == joinRef for the join push).
    // `nextRef()` is nonisolated — no actor hop needed.
    let ref = realtime.nextRef()
    joinRef = ref

    // Build the join payload.
    let accessToken = try await realtime.accessTokenForJoin()
    let joinPayload = JoinPayload.make(from: options, accessToken: accessToken)

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

    // Transition to joining before sending (so observers see the state change).
    transition(to: .joining)

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

  // MARK: - Frame router entry point

  /// Called by the frame router when a message arrives for this channel's topic.
  /// Expanded in Task 19: fan-out to messages() consumers.
  func receive(_ message: PhoenixMessage) {
    _ = message
  }
}
