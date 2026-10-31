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
  /// Open the presence streams before calling this method; they shape the join request. A
  /// Postgres changes stream opened later makes the channel rejoin. Calling it on an already-subscribed channel is a no-op, and a second
  /// concurrent call waits for the first attempt instead of starting another.
  ///
  /// When the channel has Postgres changes streams, the method returns only once the server
  /// reports that those changes are live. If the server reports a failure, or does not report
  /// within ``RealtimeChannelConfiguration/PostgresChanges/subscriptionTimeout``, the channel
  /// leaves the topic and the method throws without a retry. The same holds for the rejoins the
  /// SDK starts itself, after a reconnect or for a new Postgres changes stream: the channel ends
  /// ``RealtimeChannelStatus/failed(_:)``. Watch ``statusChanges()`` and call this method again.
  ///
  /// There is no attempt limit. After a timeout, a lost connection, or a transient join error,
  /// the channel joins again after 1, 2 and 5 s, then every 10 s; after a rate limit it waits
  /// 30 s. An expired token gets one rejoin at once, with a token fetched again from the
  /// `accessToken` callback. Cancel the calling task to stop waiting.
  ///
  /// A channel removed from its client, or closed by the server, never joins again; get a new one
  /// from ``RealtimeClient/channel(_:configure:)``.
  ///
  /// - Throws: ``RealtimeError`` when a retry cannot help: the server refused the join for good
  ///   (``RealtimeError/isRetryable`` is `false`, for example ``RealtimeError/ServerCode/unauthorized``
  ///   from an RLS policy), the token was still expired after the rejoin, the server refused the
  ///   WebSocket upgrade, the client is disconnected and `connectOnSubscribe` is off, or
  ///   ``RealtimeClient/disconnect(code:reason:)`` was called during the join, or the server
  ///   could not set up the channel's Postgres changes in time.
  ///   ``RealtimeError/Kind-swift.struct/channelClosedByServer`` when the server closed the
  ///   channel during the join, and `CancellationError` when the calling task is cancelled, when
  ///   an ``unsubscribe()`` or a removal stops the join, or when the channel was already removed.
  public func subscribe() async throws {
    guard !isRemoved else {
      logger.debug("Subscribe refused for channel '\(topic)': the channel was removed")
      throw CancellationError()
    }
    subscribeRequested = true
    switch state {
    case .subscribed:
      logger.debug("Subscribe no-op for channel '\(topic)': already subscribed")

    case .subscribing(let task, _):
      logger.debug("Subscribe already in progress for channel '\(topic)', awaiting…")
      try await awaitSharedSubscribe(task)

    case .unsubscribing(let task):
      logger.debug("Waiting for in-flight unsubscribe on '\(topic)' before subscribing")
      await task.value
      // Re-dispatch rather than calling `beginSubscribe()` directly: another caller may have
      // moved the state, or removed the channel, while this one awaited the unsubscribe.
      try await subscribe()

    case .unsubscribed, .failed:
      logger.debug("Subscribe requested for channel '\(topic)'")
      try await beginSubscribe()
    }
  }

  /// Leaves the Realtime topic and transitions the channel to
  /// ``RealtimeChannelStatus/unsubscribed``. Cancels an in-flight subscribe if one is running.
  public func unsubscribe() async {
    // No suspension before the transition: the request and the state it leaves change in one
    // turn, so a reconnect or a `subscribe()` never runs in between.
    subscribeRequested = false
    // A later subscribe is a new subscription, not a rejoin.
    hasBeenSubscribed = false
    deliverPresence(presence.clear())
    switch state {
    case .unsubscribed:
      logger.debug("Unsubscribe no-op for channel '\(topic)': already unsubscribed")

    case .failed:
      setState(.unsubscribed)

    case .unsubscribing(let task):
      logger.debug("Unsubscribe already in progress for channel '\(topic)', awaiting…")
      await task.value

    case .subscribing(let task, _):
      logger.debug("Cancelling in-flight subscribe to unsubscribe '\(topic)'")
      task.cancel()
      // Subscribe hadn't completed yet, so the server may not recognize the channel and will
      // likely never send `phx_close`. Don't wait for it.
      await startUnsubscribe(waitForServerClose: false).value

    case .subscribed:
      // We had a live subscription; wait (bounded) for the server's `phx_close` so observers see
      // the full status trail.
      await startUnsubscribe(waitForServerClose: true).value
    }
  }

  // MARK: - Client signals

  /// Resets the channel so it can rejoin after a reconnect.
  ///
  /// A channel that is `.subscribed` when the socket reconnects must re-send `phx_join` on the
  /// new socket, but ``subscribe()`` is a no-op for `.subscribed` channels, so the client resets
  /// it first. An in-flight join is waiting for a reply that will never arrive on the dead
  /// socket; cancel it so a fresh `phx_join` goes out on the new connection. An unsubscribe
  /// waiting for the server's `phx_close` ends here: that close died with the socket.
  ///
  /// - Returns: Whether the channel should rejoin: only when the caller subscribed it and has
  ///   neither unsubscribed nor removed it since, so a reconnect never joins a channel the caller
  ///   does not want or the client no longer routes to.
  @discardableResult
  func resetForReconnect() -> Bool {
    joinRef = nil
    failPendingPushes(with: RealtimeError.notConnected)
    switch state {
    case .subscribed:
      setState(.unsubscribed)
    case .subscribing(let task, _):
      task.cancel()
      failJoinWaiter(SubscribeFailure.channelClosed)
      setState(.unsubscribed)
    case .unsubscribing:
      setState(.unsubscribed)
      resumeCloseWaiter()
    case .unsubscribed, .failed:
      break
    }
    return subscribeRequested && !isRemoved
  }

  /// Resets the channel after a reconnect and joins again if the caller still wants it joined.
  ///
  /// The reset and the start of the join run in one turn of this actor. An ``unsubscribe()`` or a
  /// removal that arrives after the reset finds the join in flight and stops it; it never finds
  /// an `.unsubscribed` channel whose rejoin is still to come.
  func rejoinAfterReconnect() async throws {
    guard resetForReconnect() else { return }
    logger.debug("Rejoining channel '\(topic)' after a reconnect")
    try await awaitSubscribe(startSubscribeTask())
  }

  /// The socket was closed by ``RealtimeClient/disconnect(code:reason:)``: nothing in flight can
  /// be answered any more, and a subscribe in flight stops instead of connecting again.
  ///
  /// The server drops the join with the socket, so a subscribed channel becomes `.unsubscribed`:
  /// ``subscribe()`` joins it again after the next ``RealtimeClient/connect()``, and that join
  /// emits ``RealtimeChannelEvent/resubscribed``.
  func socketDidDisconnect() {
    failPendingPushes(with: RealtimeError.notConnected)
    // The client restarts its refs, so the next join can reuse this one.
    confirmedJoinRef = nil
    switch state {
    case .subscribing(let task, _):
      abortSubscribe(task, with: RealtimeError.disconnectedWhileSubscribing)
    case .subscribed:
      break
    case .unsubscribed, .unsubscribing, .failed:
      return
    }
    joinRef = nil
    setState(.unsubscribed)
  }

  /// The client removes the channel. It leaves the topic and never joins again: once unmapped,
  /// it would never see a reply, and each retried `phx_join` would be a duplicate join that
  /// closes the topic's next channel.
  func unsubscribeForRemoval() async {
    isRemoved = true
    await unsubscribe()
  }

  // MARK: - Server signals

  /// Called when the server confirms the `phx_join` (`system` ok, or a `phx_reply` carrying
  /// `postgres_changes`).
  func didReceiveSubscribedOK() {
    guard case .subscribing = state else { return }
    logger.debug("Server confirmed subscribe for channel '\(topic)'")
    setState(.subscribed)
    confirmedJoinRef = joinRef
    joinWaiter?.continuation.resume()
    joinWaiter = nil
    if hasBeenSubscribed {
      yield(.resubscribed)
    }
    hasBeenSubscribed = true
    // A stream opened while the join was in flight may carry a binding the join did not.
    rejoinIfBindingsChanged()
  }

  /// Rejoins a subscribed channel when an open Postgres changes stream has a binding its join
  /// did not carry, so the server sends those changes too. Closing a stream never rejoins.
  ///
  /// The channel leaves the old join and joins again with every open binding. It stays
  /// ``RealtimeChannelStatus/subscribing(attempt:)`` until the new join is confirmed, then emits
  /// ``RealtimeChannelEvent/resubscribed``.
  func rejoinIfBindingsChanged() {
    guard case .subscribed = state, let oldJoinRef = joinRef else { return }
    let joined = Set(joinedBindings.map(BindingKey.init))
    guard clientChanges.contains(where: { !joined.contains(BindingKey($0)) }) else { return }
    logger.debug("Rejoining channel '\(topic)' to add Postgres changes bindings")
    // From here, a `phx_close` for the old join is stale.
    joinRef = nil
    let task = startSubscribeTask(leaving: oldJoinRef)
    Task {
      if case .failure(let error) = await task.result {
        _ = self.subscribeDidFail(task, with: error)
      }
    }
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
    if case .subscribing(let task, _) = state {
      abortSubscribe(task, with: RealtimeError.channelClosedByServer)
      setState(.failed(RealtimeError.channelClosedByServer))
    } else {
      setState(.unsubscribed)
    }
    resumeCloseWaiter()
    return true
  }

  // MARK: - Subscribe flow

  /// Stops the subscribe in flight. Its callers get `error` rather than a bare
  /// `CancellationError`, so they can tell the abort apart from their own cancellation.
  private func abortSubscribe(_ task: Task<Void, any Error>, with error: RealtimeError) {
    abortedSubscribe = (task, error)
    task.cancel()
    failJoinWaiter(SubscribeFailure.channelClosed)
    for (id, waiter) in sharedSubscribeWaiters where waiter.task == task {
      sharedSubscribeWaiters[id] = nil
      waiter.continuation.resume(throwing: error)
    }
  }

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
        sharedSubscribeWaiters[id] = (task, continuation)
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
    sharedSubscribeWaiters.removeValue(forKey: id)?.continuation.resume(with: result)
  }

  private func beginSubscribe() async throws {
    logger.debug("Beginning subscribe flow for channel '\(topic)'")
    try await awaitSubscribe(startSubscribeTask())
  }

  private func awaitSubscribe(_ task: Task<Void, any Error>) async throws {
    do {
      // Forward cancellation of the caller's task to the spawned subscribe task. Without this,
      // `task.value` would keep waiting for the inner retry loop even after the caller cancels.
      try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
      }
    } catch {
      throw subscribeDidFail(task, with: error)
    }
  }

  /// Starts the join attempts and moves the channel to `.subscribing`. With `oldJoinRef`, the
  /// task first leaves that join, so its `phx_leave` goes out before the new `phx_join`.
  private func startSubscribeTask(leaving oldJoinRef: String? = nil) -> Task<Void, any Error> {
    let task = Task<Void, any Error> {
      if let oldJoinRef {
        await pushLeave(joinRef: oldJoinRef)
      }
      try await runSubscribeAttempts()
    }
    setState(.subscribing(task, .joining(attempt: 1)))
    return task
  }

  /// Moves the state on after the subscribe `task` failed with `error`, and returns the error
  /// its callers get.
  private func subscribeDidFail(_ task: Task<Void, any Error>, with error: any Error) -> any Error {
    let abortError = abortedSubscribe?.task == task ? abortedSubscribe?.error : nil
    if abortError != nil {
      abortedSubscribe = nil
    }

    // If the attempt didn't reach `.subscribed`, move the state on: `.failed` when a retry
    // cannot help, `.unsubscribed` when the caller cancelled. Only when the state is still
    // this attempt's: a reset or close may have replaced it with a newer attempt, which owns
    // the state now (issue #1556).
    if case .subscribing(let current, _) = state, current == task {
      joinRef = nil
      failPendingPushes(with: RealtimeError.notSubscribed)
      if let failure = error as? RealtimeError {
        setState(.failed(failure))
      } else {
        setState(.unsubscribed)
      }
    }

    // The subscribe was aborted by `didReceiveClose()` or `socketDidDisconnect()`, not by the
    // caller. Depending on how the cancellation is observed, the task can exit with
    // `CancellationError` or `SubscribeFailure.channelClosed`. Both are consequences of the
    // abort, so translate unconditionally; a genuine caller-side cancellation never records its
    // task here and still propagates as `CancellationError`.
    if let abortError {
      return abortError
    }
    return error
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
      setSubscribeProgress(.joining(attempt: attempt))

      let delay: Duration
      let lastError: RealtimeError
      do {
        let ref = try await withTimeout(joinTimeout, clock: clock) {
          try await runOneSubscribeAttempt()
        }
        try await awaitPostgresChangesIfNeeded(for: ref)
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
        lastError = error
      } catch is TimeoutError {
        logger.debug("Subscribe attempt \(attempt) timed out for channel '\(topic)'")
        delay = Self.rejoinBackoff.delay(forAttempt: attempt)
        lastError = .joinTimeout
      } catch let error as SubscribeFailure {
        logger.debug("Subscribe attempt \(attempt) failed for channel '\(topic)': \(error)")
        delay = Self.rejoinBackoff.delay(forAttempt: attempt)
        lastError = .notConnected
      }
      // One fresh-token rejoin per run of expired-token errors: a token that expires again after
      // other failures gets another one.
      hasRefreshedToken = false

      logger.debug("Retrying subscribe for '\(topic)' in \(delay)")
      setSubscribeProgress(.waiting(attempt: attempt, retryIn: delay, lastError: lastError))
      // A genuine cancellation of this task propagates out of `sleep` as `CancellationError`;
      // the next attempt re-checks the socket itself.
      try await clock.sleep(for: delay)
    }
  }

  /// Reports the subscribe loop's progress. A loop that was cancelled no longer owns the state.
  private func setSubscribeProgress(_ progress: SubscribeProgress) {
    guard !Task.isCancelled, case .subscribing(let task, _) = state else { return }
    setState(.subscribing(task, progress))
  }

  /// Sends one `phx_join` and waits for its reply. Returns the join's ref.
  private func runOneSubscribeAttempt() async throws -> String {
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
    joinReplyRef = nil
    await performJoin(ref: ref, accessToken: accessToken)

    // Wait for the join reply. A close, a reset or cancellation fails the waiter.
    try await awaitJoinConfirmation(for: ref, stage: .reply)
    return ref
  }

  /// The client-side join timeout. A join that asks the server to wait for its Postgres changes
  /// gets the server's wait on top.
  private var joinTimeout: Duration {
    timeout
      + RealtimeJoinConfig(
        configuration, bindings: clientChanges, presenceEnabled: hasPresenceListener
      ).extraJoinTimeout
  }

  /// After the join reply, waits for "Subscribed to PostgreSQL" when the join has Postgres
  /// changes bindings the server has not confirmed yet.
  ///
  /// - Throws: A non-retryable ``RealtimeError`` when the server reports a failure or the
  ///   confirmation does not arrive within ``RealtimeChannelConfiguration/PostgresChanges/subscriptionTimeout``.
  ///   The channel leaves the topic first, so the server drops the half-set-up join.
  private func awaitPostgresChangesIfNeeded(for ref: String) async throws {
    // A rejoin may already own the state: its join is not this attempt's to wait for.
    guard awaitingPostgresChanges, case .subscribing = state, joinRef == ref else { return }
    do {
      try await withTimeout(configuration.postgresChanges.subscriptionTimeout, clock: clock) {
        try await self.awaitJoinConfirmation(for: ref, stage: .postgresChanges)
      }
    } catch let error as RealtimeError {
      if confirmedJoinRef == ref { return }
      await leaveFailedJoin(ref)
      throw error
    } catch is TimeoutError {
      // The confirmation can land on the actor after the timer fired but before this catch.
      // The join is live then, and a rejoin it started may already own the state.
      if confirmedJoinRef == ref { return }
      await leaveFailedJoin(ref)
      throw RealtimeError.postgresChangesTimeout
    } catch is CancellationError {
      // The server accepted the join, so leave it when the caller cancels. An abort of this
      // attempt needs no leave: a close already ended the join, and a disconnect would buffer
      // the frame for the next connection. An abort of an older attempt still in flight does
      // not count.
      if !isAbortedSubscribeCurrent {
        await leaveFailedJoin(ref)
      }
      throw CancellationError()
    }
  }

  /// Leaves the join `ref` after its Postgres changes failed. The join is dropped before
  /// `phx_leave` goes out, so a confirmation that lands while it is sent is stale.
  private var isAbortedSubscribeCurrent: Bool {
    guard let aborted = abortedSubscribe?.task, case .subscribing(let current, _) = state else {
      return false
    }
    return aborted == current
  }

  private func leaveFailedJoin(_ ref: String) async {
    guard joinRef == ref else { return }
    joinRef = nil
    awaitingPostgresChanges = false
    await pushLeave(joinRef: ref)
  }

  /// Parks until the server sends the confirmation `stage` names for the join `ref`. A close, a
  /// reset or cancellation fails the wait.
  private func awaitJoinConfirmation(for ref: String, stage: JoinStage) async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        awaitJoinConfirmation(for: ref, stage: stage, with: continuation)
      }
    } onCancel: {
      // Lands on the actor later. Keyed on `ref` so a handler left over from a cancelled attempt
      // cannot fail the waiter of the attempt that replaced it.
      Task { await self.failJoinWaiter(CancellationError(), for: ref) }
    }
  }

  /// Parks `continuation` until the server sends the confirmation `stage` names for `ref`.
  /// Resumes it at once when the confirmation or a join error already arrived, and fails it at
  /// once if the join is already gone or the task is already cancelled.
  private func awaitJoinConfirmation(
    for ref: String, stage: JoinStage, with continuation: CheckedContinuation<Void, any Error>
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
    if stage == .reply, joinReplyRef == ref, joinRef == ref {
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
    joinWaiter = (ref, stage, continuation)
  }

  /// Builds the `phx_join` payload from the configuration and the open streams, and pushes it.
  private func performJoin(ref: String, accessToken: String?) async {
    guard let client else { return }
    logger.debug("Sending phx_join for channel '\(topic)' (ref: \(ref))")

    let joinConfig = RealtimeJoinConfig(
      configuration, bindings: clientChanges, presenceEnabled: hasPresenceListener)
    joinedBindings = joinConfig.postgresChanges
    awaitingPostgresChanges =
      !joinConfig.postgresChanges.isEmpty && !configuration.postgresChanges.waitForSubscription

    let payload = RealtimeJoinPayload(
      config: joinConfig,
      accessToken: accessToken,
      version: client.headers[.xClientInfo]
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
    switch status {
    case .connected:
      return true
    case .connecting, .reconnecting:
      // The client is connecting, or reconnecting after a drop: wait for it.
      if !connectOnSubscribe { return false }
    case .disconnected:
      break
    }
    guard connectOnSubscribe else {
      throw RealtimeError.notConnectedToSubscribe
    }
    do {
      try await client.connect()
    } catch let error as RealtimeError where !error.isRetryable {
      throw error
    } catch {
      logger.debug("Connect for channel '\(topic)' failed: \(error)")
    }
    return await client.status.isConnected
  }

  /// Socket-status probe: never connects. Used to decide whether `phx_leave` can be delivered
  /// at all.
  private func isSocketConnected() async -> Bool {
    await client?.status.isConnected ?? false
  }

  /// Fails the parked join waiter. With `ref`, only if the parked waiter belongs to that join;
  /// the waiter of a newer join is left alone.
  func failJoinWaiter(_ error: any Error, for ref: String? = nil) {
    if let ref, ref != joinWaiter?.ref { return }
    joinWaiter?.continuation.resume(throwing: error)
    joinWaiter = nil
  }

  // MARK: - Unsubscribe flow

  /// Starts an unsubscribe run and moves to `.unsubscribing`, without a suspension point.
  func startUnsubscribe(waitForServerClose: Bool) -> Task<Void, Never> {
    logger.debug("Beginning unsubscribe flow for channel '\(topic)'")
    unsubscribeRun += 1
    let run = unsubscribeRun
    let task = Task<Void, Never> {
      await runUnsubscribe(run, waitForServerClose: waitForServerClose)
    }
    setState(.unsubscribing(task))
    return task
  }

  private func runUnsubscribe(_ run: Int, waitForServerClose: Bool) async {
    // Send `phx_leave` and wait for `phx_close` only on a live socket. On a dead one the
    // server-side channel died with the connection, `phx_leave` would only be buffered into the
    // *next* connection as a stale frame, and `phx_close` can never arrive — waiting would stall
    // for the full timeout (issue #1145).
    let socketConnected = await isSocketConnected()

    // A reset or a server close may end this run at any suspension point, and a newer subscribe
    // or unsubscribe may own the state and `joinRef` since: this run must not touch them.
    guard ownsState(run) else { return }
    if socketConnected {
      await push(ChannelEvent.leave)
    }

    // Wait (bounded by `timeout`) for the server's `phx_close` to arrive via `didReceiveClose()`.
    if waitForServerClose, socketConnected {
      _ = try? await withTimeout(timeout, clock: clock) {
        await withTaskCancellationHandler {
          await withCheckedContinuation { continuation in
            guard ownsState(run) else {
              continuation.resume()
              return
            }
            closeWaiter = (run, continuation)
          }
        } onCancel: {
          Task { await self.resumeCloseWaiter(for: run) }
        }
      }
    }

    guard ownsState(run) else { return }
    joinRef = nil
    failPendingPushes(with: RealtimeError.notSubscribed)
    setState(.unsubscribed)
  }

  /// Whether the state is still `.unsubscribing` with the task of unsubscribe run `run`.
  private func ownsState(_ run: Int) -> Bool {
    guard case .unsubscribing = state else { return false }
    return run == unsubscribeRun
  }

  /// Resumes the parked close waiter. With `run`, only if the waiter belongs to that run; the
  /// waiter of a newer run is left alone.
  func resumeCloseWaiter(for run: Int? = nil) {
    if let run, run != closeWaiter?.run { return }
    closeWaiter?.continuation.resume()
    closeWaiter = nil
  }
}

/// The fields of a Postgres changes binding the server matches on. `PostgresJoinConfig`'s `==`
/// treats `.all` as matching any event, which would hide a new binding.
private struct BindingKey: Hashable {
  let event: PostgresChangeEvent?
  let schema: String
  let table: String?
  let filter: String?
  let select: [String]?

  init(_ binding: PostgresJoinConfig) {
    event = binding.event
    schema = binding.schema
    table = binding.table
    filter = binding.filter
    select = binding.select
  }
}

/// The confirmation a join attempt waits for.
enum JoinStage {
  /// The `phx_reply` to `phx_join`.
  case reply
  /// "Subscribed to PostgreSQL", after the reply, for a join with Postgres changes bindings.
  case postgresChanges
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

  /// The server confirmed the join with `postgres_changes` the client cannot decode. A retry
  /// gets the same reply.
  static func unreadableJoinReply(_ error: any Error) -> RealtimeError {
    RealtimeError(
      kind: .server,
      message: "The server's join reply has `postgres_changes` the client cannot read: \(error)",
      isRetryable: false
    )
  }

  /// ``RealtimeClient/disconnect(code:reason:)`` was called while the channel was subscribing.
  static let disconnectedWhileSubscribing = RealtimeError(
    kind: .notConnected,
    message: "The realtime client was disconnected while the channel was subscribing.",
    isRetryable: false
  )

  /// The server did not report "Subscribed to PostgreSQL" within
  /// ``RealtimeChannelConfiguration/PostgresChanges/subscriptionTimeout``.
  static let postgresChangesTimeout = RealtimeError(
    kind: .timeout,
    message:
      "The server did not set up the channel's Postgres changes within the subscription timeout.",
    isRetryable: false
  )

  /// The server could not set up the channel's Postgres changes bindings.
  package static func postgresChangesFailed(reason: String) -> RealtimeError {
    RealtimeError(
      kind: .server,
      message: "The server could not set up the channel's Postgres changes: \(reason)",
      isRetryable: false
    )
  }

  /// The server did not confirm a `phx_join` within the client's configured timeout.
  static let joinTimeout = RealtimeError(
    kind: .timeout, message: "The server did not confirm the join within the timeout.")

  /// The socket is not connected, so the push cannot be answered.
  static let notConnected = RealtimeError(
    kind: .notConnected, message: "The realtime client is not connected.")

  /// No `phx_reply` arrived for the push within the client's configured timeout.
  static let pushTimeout = RealtimeError(
    kind: .timeout, message: "The server did not reply to the push within the timeout.")
}
