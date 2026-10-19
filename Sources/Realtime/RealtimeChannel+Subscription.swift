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

/// The subscribe/unsubscribe state machine: retries, timeouts, and deduplication of concurrent
/// calls.
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
  /// cancellations — so the retry ladder treats them like timeouts and callers never see a
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
  /// - Throws: ``RealtimeError`` with kind `.timeout`, `.maxRetryAttemptsReached` or
  ///   `.channelClosedByServer`.
  public func subscribe() async throws {
    switch state {
    case .subscribed:
      logger.debug("Subscribe no-op for channel '\(topic)': already subscribed")

    case .subscribing(let task):
      logger.debug("Subscribe already in progress for channel '\(topic)', awaiting…")
      try await task.value

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
      await beginUnsubscribe(waitForServerClose: false, sendLeave: isSocketConnected)

    case .subscribed:
      // We had a live subscription; wait (bounded) for the server's `phx_close` so observers see
      // the full status trail.
      //
      // Unless the socket is dead: the server-side channel died with the connection,
      // `phx_leave` would only be buffered into the *next* connection as a stale frame, and
      // `phx_close` can never arrive — waiting would stall for the full timeout (issue #1145).
      let socketConnected = isSocketConnected
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
  /// be answered any more.
  func socketDidDisconnect() {
    failPendingPushes(with: RealtimeError.notConnected)
  }

  // MARK: - Server signals

  /// Called when the server confirms the `phx_join` (`system` ok, or a `phx_reply` carrying
  /// `postgres_changes`).
  func didReceiveSubscribedOK() {
    guard case .subscribing = state else { return }
    logger.debug("Server confirmed subscribe for channel '\(topic)'")
    setState(.subscribed)
    joinWaiter?.resume()
    joinWaiter = nil
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
      closedByServerWhileSubscribing = true
      task.cancel()
      failJoinWaiter(SubscribeFailure.channelClosed)
    }
    setState(.unsubscribed)
    resumeCloseWaiter()
    return true
  }

  // MARK: - Subscribe flow

  private func beginSubscribe() async throws {
    logger.debug("Beginning subscribe flow for channel '\(topic)'")
    closedByServerWhileSubscribing = false
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
      let closedByServer = closedByServerWhileSubscribing
      closedByServerWhileSubscribing = false

      // If the attempt didn't reach `.subscribed`, make sure observers see `.unsubscribed`.
      if case .subscribing = state {
        joinRef = nil
        failPendingPushes(with: RealtimeError.notSubscribed)
        setState(.unsubscribed)
      }

      // The subscribe was aborted by `didReceiveClose()`, not by the caller. Depending on how
      // the cancellation is observed, the task can exit with `CancellationError`,
      // `SubscribeFailure.channelClosed`, or — when the close lands on the final retry attempt —
      // `maxRetryAttemptsReached`. All of them are consequences of the server close, so
      // translate unconditionally; a genuine caller-side cancellation never sets the flag and
      // still propagates as `CancellationError`.
      if closedByServer {
        throw RealtimeError.channelClosedByServer
      }
      throw error
    }
  }

  private func runSubscribeAttempts() async throws {
    var attempts = 0
    while attempts < maxRetryAttempts {
      attempts += 1

      do {
        try Task.checkCancellation()
        logger.debug("Subscribe attempt \(attempts)/\(maxRetryAttempts) for channel '\(topic)'")

        try await withTimeout(timeout, clock: clock) {
          try await runOneSubscribeAttempt()
        }

        logger.debug("Subscribe succeeded for channel '\(topic)'")
        return
      } catch let error where error is TimeoutError || error is SubscribeFailure {
        logger.debug(
          "Subscribe attempt failed for channel '\(topic)' (attempt \(attempts)/\(maxRetryAttempts)): \(error)"
        )

        guard attempts < maxRetryAttempts else {
          logger.error(
            "Failed to subscribe to channel '\(topic)' after \(maxRetryAttempts) attempts")
          throw RealtimeError.maxRetryAttemptsReached
        }

        let delay = retryDelay(attempts)
        logger.debug("Retrying subscribe for '\(topic)' in \(delay)")

        // A genuine cancellation of this task propagates out of `sleep` as `CancellationError`;
        // the next attempt re-checks the socket itself.
        try await clock.sleep(for: delay)
      }
    }

    throw RealtimeError.maxRetryAttemptsReached
  }

  private func runOneSubscribeAttempt() async throws {
    guard await ensureSocketConnected() else {
      throw SubscribeFailure.socketNotConnected
    }
    guard let client else {
      throw SubscribeFailure.socketNotConnected
    }

    let ref = await client.makeRef()
    joinRef = ref
    await performJoin(ref: ref)

    // Wait for `didReceiveSubscribedOK`. A close, a reset or cancellation fails the waiter.
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        awaitJoinConfirmation(for: ref, with: continuation)
      }
    } onCancel: {
      Task { await self.failJoinWaiter(CancellationError()) }
    }
  }

  /// Parks `continuation` until the server confirms the join for `ref`, or fails it at once if
  /// the join is already gone or the task is already cancelled.
  private func awaitJoinConfirmation(
    for ref: String, with continuation: CheckedContinuation<Void, any Error>
  ) {
    guard case .subscribing = state, joinRef == ref else {
      continuation.resume(throwing: SubscribeFailure.channelClosed)
      return
    }
    if Task.isCancelled {
      continuation.resume(throwing: CancellationError())
      return
    }
    joinWaiter = continuation
  }

  /// Builds the `phx_join` payload from the config and the open streams, and pushes it.
  private func performJoin(ref: String) async {
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
      accessToken: await client.currentAccessToken(),
      version: client.options.headers[.xClientInfo]
    )

    guard let encodedPayload = try? JSONObject(payload) else {
      reportIssue("Failed to encode the phx_join payload for channel '\(topic)'. Skipping join.")
      return
    }

    await push(ChannelEvent.join, ref: ref, payload: encodedPayload)
  }

  /// Connects the socket when the client allows it, and reports whether it is connected.
  private func ensureSocketConnected() async -> Bool {
    guard let client else { return false }
    if client.statusSnapshot == .connected { return true }
    guard connectOnSubscribe else {
      reportIssue(
        "You can't subscribe to a channel while the realtime client is not connected. Did you forget to call `realtime.connect()`?"
      )
      return false
    }
    try? await client.connect()
    return client.statusSnapshot == .connected
  }

  /// Synchronous socket-status probe: never connects. Used to decide whether `phx_leave` can be
  /// delivered at all.
  private var isSocketConnected: Bool {
    client?.statusSnapshot == .connected
  }

  func failJoinWaiter(_ error: any Error) {
    joinWaiter?.resume(throwing: error)
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

  /// The socket is not connected, so the push cannot be answered.
  static let notConnected = RealtimeError(
    kind: .notConnected, message: "The realtime client is not connected.")

  /// No `phx_reply` arrived for the push within the client's configured timeout.
  static let pushTimeout = RealtimeError(
    kind: .timeout, message: "The server did not reply to the push within the timeout.")
}
