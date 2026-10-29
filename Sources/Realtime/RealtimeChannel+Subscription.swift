//
//  RealtimeChannel+Subscription.swift
//  Realtime
//
//  Created by Guilherme Souza on 19/10/26.
//

import Foundation
import Helpers
import Logging
import IssueReporting

/// The subscribe/unsubscribe state machine: join errors, retries, timeouts, and deduplication of
/// concurrent calls.
///
/// State transitions are:
///
///   unsubscribed → subscribing → subscribed → unsubscribing → unsubscribed
///
/// The ``RealtimeChannel/SubscriptionState/subscribing(_:)`` and
/// ``RealtimeChannel/SubscriptionState/unsubscribing(_:)`` cases carry the in-flight task so
/// concurrent callers can await it or cancel it.
extension RealtimeChannel {
  /// Typed failure for a single subscribe attempt. These are lifecycle failures — not task
  /// cancellations — so the retry loop treats them like timeouts and callers never see a
  /// spurious `CancellationError` (issue #1145, defect 2).
  enum SubscribeFailure: Error {
    /// The socket could not be connected (or reconnected) for this attempt.
    case socketNotConnected
    /// The channel transitioned to `.unsubscribed` while waiting for the join confirmation.
    case channelClosed
  }

  // MARK: - Public API

  /// Joins the Realtime topic and suspends until the subscription is confirmed by the server.
  ///
  /// Open the postgres-change and presence streams before calling this method; they shape the
  /// join request. Calling it on an already-subscribed channel is a no-op, and a second
  /// concurrent call waits for the first attempt instead of starting another.
  ///
  /// There is no attempt limit. After a timeout, a lost connection, or a transient join error,
  /// the channel joins again after 1, 2 and 5 s, then every 10 s; after a rate limit it waits
  /// 30 s. An expired token gets one rejoin at once, with a token fetched again from the
  /// `accessToken` callback. Cancel the calling task to stop waiting.
  ///
  /// - Throws: ``RealtimeError`` when a retry cannot help: the server refused the join for good
  ///   (``RealtimeError/isRetryable`` is `false`, for example ``RealtimeError/ServerCode/unauthorized``
  ///   from an RLS policy), the token was still expired after the rejoin, the server refused the
  ///   WebSocket upgrade, the client is disconnected and `connectOnSubscribe` is off, or
  ///   ``RealtimeClient/disconnect(code:reason:)`` was called during the join.
  ///   ``RealtimeError/Kind-swift.struct/channelClosedByServer`` when the server closed the
  ///   channel during the join, and `CancellationError` when the calling task is cancelled.
  public func subscribe() async throws {
    switch state {
    case .subscribed:
      logger.debug("Subscribe no-op for channel '\(topic)': already subscribed")

    case .subscribing(let task):
      logger.debug("Subscribe already in progress for channel '\(topic)', awaiting…")
      try await awaitSharedSubscribe(task)

    case .unsubscribing(let task):
      logger.debug("Waiting for in-flight unsubscribe on '\(topic)' before subscribing")
      await task.value
      // Re-dispatch rather than calling `beginSubscribe()` directly: another caller may have
      // moved the state while this one awaited the unsubscribe.
      try await subscribe()

    case .unsubscribed:
      logger.debug("Subscribe requested for channel '\(topic)'")
      try await beginSubscribe()
    }
  }

  /// Leaves the Realtime topic and transitions the channel to
  /// ``RealtimeChannelStatus/unsubscribed``. Cancels an in-flight subscribe if one is running.
  public func unsubscribe() async {
    // Probe the socket before reading `state`: the probe suspends, and another caller could move
    // the state while this one waits. After it, the switch and the transition run without a
    // suspension point.
    let socketConnected = await isSocketConnected()
    switch state {
    case .unsubscribed:
      logger.debug("Unsubscribe no-op for channel '\(topic)': already unsubscribed")

    case .unsubscribing(let task):
      logger.debug("Unsubscribe already in progress for channel '\(topic)', awaiting…")
      await task.value

    case .subscribing(let task):
      logger.debug("Cancelling in-flight subscribe to unsubscribe '\(topic)'")
      task.cancel()
      // Subscribe hadn't completed yet, so the server may not recognize the channel and will
      // likely never send `phx_close`. Don't wait for it.
      await beginUnsubscribe(waitForServerClose: false, sendLeave: socketConnected)

    case .subscribed:
      // We had a live subscription; wait (bounded) for the server's `phx_close` so observers see
      // the full status trail.
      //
      // Unless the socket is dead: the server-side channel died with the connection,
      // `phx_leave` would only be buffered into the *next* connection as a stale frame, and
      // `phx_close` can never arrive — waiting would stall for the full timeout (issue #1145).
      await beginUnsubscribe(waitForServerClose: socketConnected, sendLeave: socketConnected)
    }
  }

  // MARK: - Client signals

  /// Resets the channel so it can rejoin after a reconnect.
  ///
  /// A channel that is `.subscribed` when the socket reconnects must re-send `phx_join` on the
  /// new socket, but ``subscribe()`` is a no-op for `.subscribed` channels, so the client resets
  /// it first. An in-flight join is waiting for a reply that will never arrive on the dead
  /// socket; cancel it so a fresh `phx_join` goes out on the new connection.
  func resetForReconnect() {
    joinRef = nil
    failPendingPushes(with: RealtimeError.notConnected)
    switch state {
    case .subscribed:
      setState(.unsubscribed)
    case .subscribing(let task):
      task.cancel()
      failJoinWaiter(SubscribeFailure.channelClosed)
      setState(.unsubscribed)
    case .unsubscribing:
      setState(.unsubscribed)
      resumeCloseWaiter()
    case .unsubscribed:
      break
    }
  }

  /// The socket was closed by ``RealtimeClient/disconnect(code:reason:)``: nothing in flight can
  /// be answered any more, and a subscribe in flight stops instead of connecting again.
  func socketDidDisconnect() {
    failPendingPushes(with: RealtimeError.notConnected)
    guard case .subscribing(let task) = state else { return }
    abortedSubscribe = (task, RealtimeError.disconnectedWhileSubscribing)
    task.cancel()
    failJoinWaiter(SubscribeFailure.channelClosed)
    joinRef = nil
    setState(.unsubscribed)
  }

  // MARK: - Server signals

  /// Called when the server confirms the `phx_join` (`system` ok, or a `phx_reply` carrying
  /// `postgres_changes`).
  func didReceiveSubscribedOK() {
    guard case .subscribing = state else { return }
    logger.debug("Server confirmed subscribe for channel '\(topic)'")
    setState(.subscribed)
    joinWaiter?.continuation.resume()
    joinWaiter = nil
  }

  /// Called when the server answers the `phx_join` for `ref` with an error.
  ///
  /// Fails the waiting attempt with `error`. An error that lands while that attempt is still
  /// sending its `phx_join` is kept until it parks. Errors for any other join are ignored.
  func didReceiveJoinError(_ error: RealtimeError, for ref: String) {
    guard case .subscribing = state, joinRef == ref else { return }
    logger.debug("Server refused the join for channel '\(topic)' (ref: \(ref)): \(error.message)")
    if joinWaiter?.ref == ref {
      failJoinWaiter(error, for: ref)
    } else {
      joinFailure = (ref, error)
    }
  }

  /// Called when the server closes the channel (`phx_close`, or a `phx_error` that drops it).
  ///
  /// When `expectedJoinRef` is provided (Phoenix tags `phx_close` with the `join_ref` of the
  /// join it closes), the close is only applied if it still matches the current ``joinRef``.
  /// Closes without a `join_ref` are applied unconditionally.
  ///
  /// Returns `true` if the close was applied; `false` if it belonged to a stale join.
  @discardableResult
  func didReceiveClose(joinRef expectedJoinRef: String? = nil) -> Bool {
    if let expectedJoinRef, expectedJoinRef != joinRef {
      logger.debug(
        "Ignoring close for stale join_ref \(expectedJoinRef) on '\(topic)' (current: \(joinRef ?? "<none>"))"
      )
      return false
    }
    logger.debug("Server closed channel '\(topic)'")
    joinRef = nil
    failPendingPushes(with: RealtimeError.channelClosedByServer)
    if case .subscribing(let task) = state {
      // Record why the task is being cancelled so `beginSubscribe` can rethrow a typed error —
      // the caller must be able to tell a server close apart from its own task cancellation.
      abortedSubscribe = (task, RealtimeError.channelClosedByServer)
      task.cancel()
      failJoinWaiter(SubscribeFailure.channelClosed)
    }
    setState(.unsubscribed)
    resumeCloseWaiter()
    return true
  }

  // MARK: - Subscribe flow

  /// Waits for a subscribe that another caller started. Cancelling this caller stops its wait
  /// but not the attempt: with no attempt limit, `task.value` alone could wait forever.
  private func awaitSharedSubscribe(_ task: Task<Void, any Error>) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        guard !Task.isCancelled else {
          continuation.resume(throwing: CancellationError())
          return
        }
        sharedSubscribeWaiters[id] = continuation
        Task {
          let result = await task.result
          self.resumeSharedSubscribeWaiter(id, with: result)
        }
      }
    } onCancel: {
      Task { await self.resumeSharedSubscribeWaiter(id, with: .failure(CancellationError())) }
    }
  }

  private func resumeSharedSubscribeWaiter(_ id: UUID, with result: Result<Void, any Error>) {
    sharedSubscribeWaiters.removeValue(forKey: id)?.resume(with: result)
  }

  private func beginSubscribe() async throws {
    logger.debug("Beginning subscribe flow for channel '\(topic)'")
    let task = Task<Void, any Error> {
      try await runSubscribeAttempts()
    }
    setState(.subscribing(task))

    do {
      // Forward cancellation of the caller's task to the spawned subscribe task. Without this,
      // `task.value` would keep waiting for the inner retry loop even after the caller cancels.
      try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
      }
    } catch {
      let abortError = abortedSubscribe?.task == task ? abortedSubscribe?.error : nil
      if abortError != nil {
        abortedSubscribe = nil
      }

      // If the attempt didn't reach `.subscribed`, make sure observers see `.unsubscribed`. Only
      // when the state is still this attempt's: a reset or close may have replaced it with a
      // newer attempt, which owns the state now (issue #1556).
      if case .subscribing(let current) = state, current == task {
        joinRef = nil
        failPendingPushes(with: RealtimeError.notSubscribed)
        setState(.unsubscribed)
      }

      // The subscribe was aborted by `didReceiveClose()` or `socketDidDisconnect()`, not by the
      // caller. Depending on how the cancellation is observed, the task can exit with
      // `CancellationError` or `SubscribeFailure.channelClosed`. Both are consequences of the
      // abort, so translate unconditionally; a genuine caller-side cancellation never records its
      // task here and still propagates as `CancellationError`.
      if let abortError {
        throw abortError
      }
      throw error
    }
  }

  /// Runs join attempts until one succeeds, a join error says retrying cannot help, or the task
  /// is cancelled.
  private func runSubscribeAttempts() async throws {
    var attempt = 0
    var hasRefreshedToken = false
    while true {
      attempt += 1
      try Task.checkCancellation()
      // A late `ok` for a join that timed out confirms it while this loop waits out the backoff.
      if case .subscribed = state { return }
      logger.debug("Subscribe attempt \(attempt) for channel '\(topic)'")

      let delay: Duration
      do {
        try await withTimeout(timeout, clock: clock) {
          try await runOneSubscribeAttempt()
        }
        logger.debug("Subscribe succeeded for channel '\(topic)'")
        return
      } catch let error as RealtimeError {
        switch error.joinRecovery {
        case .refreshToken where !hasRefreshedToken:
          hasRefreshedToken = true
          logger.debug("Token expired for channel '\(topic)', rejoining with a fresh one")
          await client?.refreshTokenForRejoin()
          continue
        case .fail, .refreshToken:
          logger.error("Failed to subscribe to channel '\(topic)': \(error.message)")
          throw error
        case .backOff:
          delay = Self.rateLimitBackoff
        case .retry:
          delay = Self.rejoinBackoff.delay(forAttempt: attempt)
        }
      } catch let error where error is TimeoutError || error is SubscribeFailure {
        logger.debug("Subscribe attempt \(attempt) failed for channel '\(topic)': \(error)")
        delay = Self.rejoinBackoff.delay(forAttempt: attempt)
      }

      logger.debug("Retrying subscribe for '\(topic)' in \(delay)")
      // A genuine cancellation of this task propagates out of `sleep` as `CancellationError`;
      // the next attempt re-checks the socket itself.
      try await clock.sleep(for: delay)
    }
  }

  private func runOneSubscribeAttempt() async throws {
    guard try await ensureSocketConnected() else {
      throw SubscribeFailure.socketNotConnected
    }
    let (ref, accessToken) = try await makeJoinRefAndToken()
    // A reset or close may have cancelled this attempt while it waited above. A stale attempt
    // must not write `joinRef` over the newer attempt's ref or send a `phx_join` the server
    // would treat as a duplicate.
    try Task.checkCancellation()
    joinRef = ref
    joinAccessToken = accessToken
    joinFailure = nil
    await performJoin(ref: ref, accessToken: accessToken)

    // Wait for `didReceiveSubscribedOK`. A close, a reset or cancellation fails the waiter.
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        awaitJoinConfirmation(for: ref, with: continuation)
      }
    } onCancel: {
      // Lands on the actor later. Keyed on `ref` so a handler left over from a cancelled attempt
      // cannot fail the waiter of the attempt that replaced it.
      Task { await self.failJoinWaiter(CancellationError(), for: ref) }
    }
  }

  /// Parks `continuation` until the server confirms the join for `ref`. Resumes it at once when
  /// the confirmation or a join error already arrived while `phx_join` was being sent, and fails
  /// it at once if the join is already gone or the task is already cancelled.
  private func awaitJoinConfirmation(
    for ref: String, with continuation: CheckedContinuation<Void, any Error>
  ) {
    if let failure = joinFailure, failure.ref == ref {
      joinFailure = nil
      continuation.resume(throwing: failure.error)
      return
    }
    if case .subscribed = state, joinRef == ref {
      continuation.resume()
      return
    }
    guard case .subscribing = state, joinRef == ref else {
      continuation.resume(throwing: SubscribeFailure.channelClosed)
      return
    }
    if Task.isCancelled {
      continuation.resume(throwing: CancellationError())
      return
    }
    joinWaiter = (ref, continuation)
  }

  /// Builds the `phx_join` payload from the config and the open streams, and pushes it.
  private func performJoin(ref: String, accessToken: String?) async {
    guard let client else { return }
    logger.debug("Sending phx_join for channel '\(topic)' (ref: \(ref))")

    var presence = config.presence
    presence.enabled = hasPresenceListener

    let joinConfig = RealtimeJoinConfig(
      broadcast: config.broadcast,
      presence: presence,
      postgresChanges: clientChanges,
      isPrivate: config.isPrivate
    )

    let payload = RealtimeJoinPayload(
      config: joinConfig,
      accessToken: accessToken,
      version: client.options.headers[.xClientInfo]
    )

    guard let encodedPayload = try? JSONObject(payload) else {
      reportIssue("Failed to encode the phx_join payload for channel '\(topic)'. Skipping join.")
      return
    }

    await push(ChannelEvent.join, ref: ref, payload: encodedPayload)
  }

  /// Holds the client only while it hands out the ref and the token, so an attempt that waits
  /// for its reply does not keep a released client alive.
  private func makeJoinRefAndToken() async throws -> (ref: String, accessToken: String?) {
    guard let client else { throw RealtimeError.clientReleased }
    return (await client.makeRef(), await client.currentAccessToken())
  }

  /// Connects the socket when the client allows it, and reports whether it is connected.
  ///
  /// - Throws: ``RealtimeError`` when no retry can connect: the client is gone,
  ///   `connectOnSubscribe` is off, or the server refused the upgrade for good.
  private func ensureSocketConnected() async throws -> Bool {
    guard let client else { throw RealtimeError.clientReleased }
    let status = await client.status
    if status == .connected { return true }
    guard connectOnSubscribe else {
      // The client is connecting, or reconnecting after a drop: wait for it.
      if status == .connecting { return false }
      reportIssue(
        "You can't subscribe to a channel while the realtime client is not connected. Did you forget to call `realtime.connect()`?"
      )
      throw RealtimeError.notConnectedToSubscribe
    }
    do {
      try await client.connect()
    } catch let error as RealtimeError where !error.isRetryable {
      throw error
    } catch {
      logger.debug("Connect for channel '\(topic)' failed: \(error)")
    }
    return await client.status == .connected
  }

  /// Socket-status probe: never connects. Used to decide whether `phx_leave` can be delivered
  /// at all.
  private func isSocketConnected() async -> Bool {
    await client?.status == .connected
  }

  /// Fails the parked join waiter. With `ref`, only if the parked waiter belongs to that join;
  /// the waiter of a newer join is left alone.
  func failJoinWaiter(_ error: any Error, for ref: String? = nil) {
    if let ref, ref != joinWaiter?.ref { return }
    joinWaiter?.continuation.resume(throwing: error)
    joinWaiter = nil
  }

  // MARK: - Unsubscribe flow

  private func beginUnsubscribe(waitForServerClose: Bool, sendLeave: Bool) async {
    logger.debug("Beginning unsubscribe flow for channel '\(topic)'")
    let task = Task<Void, Never> {
      await runUnsubscribe(waitForServerClose: waitForServerClose, sendLeave: sendLeave)
    }
    setState(.unsubscribing(task))
    await task.value
  }

  private func runUnsubscribe(waitForServerClose: Bool, sendLeave: Bool) async {
    // Send `phx_leave` (skipped when the socket is dead — it could never be delivered, only
    // buffered into the next connection as a stale frame). When `waitForServerClose` is true,
    // wait (bounded by `timeout`) for the server's `phx_close` to arrive via `didReceiveClose()`.
    if sendLeave {
      await push(ChannelEvent.leave)
    }

    if waitForServerClose {
      _ = try? await withTimeout(timeout, clock: clock) {
        await withTaskCancellationHandler {
          await withCheckedContinuation { continuation in
            guard case .unsubscribing = state else {
              continuation.resume()
              return
            }
            closeWaiter = continuation
          }
        } onCancel: {
          Task { await self.resumeCloseWaiter() }
        }
      }
    }

    joinRef = nil
    failPendingPushes(with: RealtimeError.notSubscribed)
    if case .unsubscribing = state {
      setState(.unsubscribed)
    }
  }

  func resumeCloseWaiter() {
    closeWaiter?.resume()
    closeWaiter = nil
  }
}

extension RealtimeError {
  /// The channel is not subscribed, so the push cannot be delivered.
  static let notSubscribed = RealtimeError(
    kind: .notSubscribed,
    message: "The channel is not subscribed. Call `subscribe()` first, or use `httpSend()`.",
    isRetryable: false
  )

  /// The channel's client was released, so the channel can never connect again.
  static let clientReleased = RealtimeError(
    kind: .notConnected, message: "The realtime client was released.", isRetryable: false)

  /// `subscribe()` found no connection and `connectOnSubscribe` is off.
  static let notConnectedToSubscribe = RealtimeError(
    kind: .notConnected,
    message:
      "The realtime client is not connected and `connectOnSubscribe` is off. Call `connect()` first.",
    isRetryable: false
  )

  /// ``RealtimeClient/disconnect(code:reason:)`` was called while the channel was subscribing.
  static let disconnectedWhileSubscribing = RealtimeError(
    kind: .notConnected,
    message: "The realtime client was disconnected while the channel was subscribing.",
    isRetryable: false
  )

  /// The socket is not connected, so the push cannot be answered.
  static let notConnected = RealtimeError(
    kind: .notConnected, message: "The realtime client is not connected.")

  /// No `phx_reply` arrived for the push within the client's configured timeout.
  static let pushTimeout = RealtimeError(
    kind: .timeout, message: "The server did not reply to the push within the timeout.")
}
