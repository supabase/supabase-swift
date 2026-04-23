import ConcurrencyExtras
import Foundation

/// Owns the subscription state machine for ``RealtimeChannelV2``.
///
/// The actor drives subscribe/unsubscribe lifecycles end-to-end: retries,
/// timeouts, and deduplication of concurrent calls. Network side-effects
/// (pushing `phx_join` / `phx_leave`, ensuring the socket is connected,
/// generating refs) are injected as closures at init time so the state
/// machine stays independent of the concrete channel.
///
/// State transitions are:
///
///   unsubscribed → subscribing → subscribed → unsubscribing → unsubscribed
///
/// The ``subscribing`` and ``unsubscribing`` cases carry the in-flight
/// ``Task`` so concurrent callers can either await it or cancel it.
actor ChannelStateManager {
  enum State: Sendable, CustomStringConvertible {
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
  }

  typealias MakeRef = @Sendable () -> String
  typealias EnsureSocketConnected = @Sendable () async -> Bool
  typealias JoinOperation =
    @Sendable (_ joinRef: String, _ clientChanges: [PostgresJoinConfig])
    async -> Void
  typealias LeaveOperation = @Sendable () async -> Void
  typealias RetryDelay = @Sendable (_ attempt: Int) -> TimeInterval
  /// Synchronous callback invoked every time the state changes. The channel
  /// uses this to push status updates to observers without an async hop, so
  /// reading ``RealtimeChannelV2/status`` right after ``subscribe()`` returns
  /// sees the latest value.
  typealias StateDidChange = @Sendable (State) -> Void

  private let stateSubject = AsyncValueSubject<State>(.unsubscribed)
  private let stateDidChange: StateDidChange?

  /// Current state. Reading from outside the actor crosses the actor boundary.
  var state: State { stateSubject.value }

  /// Publishes every state transition, replaying the current state to new
  /// subscribers.
  nonisolated var stateChanges: AsyncStream<State> { stateSubject.values }

  // MARK: - Per-subscription mutable state

  private(set) var joinRef: String?
  private(set) var clientChanges: [PostgresJoinConfig] = []
  private var pushes: [String: PushV2] = [:]

  // MARK: - Config & injected operations

  private let logger: (any SupabaseLogger)?
  private let topic: String
  private let maxRetryAttempts: Int
  private let timeoutInterval: TimeInterval

  private let makeRef: MakeRef
  private let ensureSocketConnected: EnsureSocketConnected
  private let joinOperation: JoinOperation
  private let leaveOperation: LeaveOperation
  private let retryDelay: RetryDelay

  init(
    topic: String,
    logger: (any SupabaseLogger)?,
    maxRetryAttempts: Int,
    timeoutInterval: TimeInterval,
    makeRef: @escaping MakeRef,
    ensureSocketConnected: @escaping EnsureSocketConnected,
    joinOperation: @escaping JoinOperation,
    leaveOperation: @escaping LeaveOperation,
    retryDelay: @escaping RetryDelay = ChannelStateManager.defaultRetryDelay,
    stateDidChange: StateDidChange? = nil
  ) {
    self.topic = topic
    self.logger = logger
    self.maxRetryAttempts = maxRetryAttempts
    self.timeoutInterval = timeoutInterval
    self.makeRef = makeRef
    self.ensureSocketConnected = ensureSocketConnected
    self.joinOperation = joinOperation
    self.leaveOperation = leaveOperation
    self.retryDelay = retryDelay
    self.stateDidChange = stateDidChange
  }

  // MARK: - Mutable state accessors

  func addClientChange(_ config: PostgresJoinConfig) {
    clientChanges.append(config)
  }

  func storePush(_ push: PushV2, ref: String) {
    pushes[ref] = push
  }

  func removePush(ref: String) -> PushV2? {
    pushes.removeValue(forKey: ref)
  }

  // MARK: - Public API

  /// Drive the channel to ``State/subscribed``. Safe to call concurrently:
  /// the second caller waits for the first attempt to finish instead of
  /// starting a new one.
  func subscribe() async throws {
    switch state {
    case .subscribed:
      logger?.debug("Subscribe no-op for channel '\(topic)': already subscribed")
      return

    case .subscribing(let task):
      logger?.debug("Subscribe already in progress for channel '\(topic)', awaiting…")
      try await task.value
      return

    case .unsubscribing(let task):
      logger?.debug("Waiting for in-flight unsubscribe on '\(topic)' before subscribing")
      await task.value
      try await beginSubscribe()

    case .unsubscribed:
      try await beginSubscribe()
    }
  }

  /// Drive the channel to ``State/unsubscribed``. Cancels an in-flight
  /// subscribe if one is running.
  func unsubscribe() async {
    switch state {
    case .unsubscribed:
      logger?.debug("Unsubscribe no-op for channel '\(topic)': already unsubscribed")
      return

    case .unsubscribing(let task):
      logger?.debug("Unsubscribe already in progress for channel '\(topic)', awaiting…")
      await task.value
      return

    case .subscribing(let task):
      logger?.debug("Cancelling in-flight subscribe to unsubscribe '\(topic)'")
      task.cancel()
      // Subscribe hadn't completed yet, so the server may not recognise the
      // channel and will likely never send `phx_close`. Don't wait for it.
      await beginUnsubscribe(waitForServerClose: false)

    case .subscribed:
      // We had a live subscription; wait (bounded) for the server's
      // `phx_close` to arrive so observers see the full status trail.
      await beginUnsubscribe(waitForServerClose: true)
    }
  }

  // MARK: - Server signals

  /// Called when the server confirms the `phx_join` (system.ok or phx_reply
  /// with `postgres_changes`).
  func didReceiveSubscribedOK() {
    guard case .subscribing = state else { return }
    logger?.debug("Server confirmed subscribe for channel '\(topic)'")
    updateState(.subscribed)
  }

  /// Called when the server closes the channel (phx_close or system error
  /// that should drop the channel).
  func didReceiveClose() {
    logger?.debug("Server closed channel '\(topic)'")
    joinRef = nil
    pushes = [:]
    if case .subscribing(let task) = state {
      task.cancel()
    }
    updateState(.unsubscribed)
  }

  // MARK: - Private

  private func beginSubscribe() async throws {
    logger?.debug("Beginning subscribe flow for channel '\(topic)'")
    let task = Task<Void, any Error> { [weak self] in
      guard let self else { return }
      try await self.runSubscribeAttempts()
    }
    updateState(.subscribing(task))

    do {
      // Forward cancellation of the caller's task to the spawned subscribe
      // task. Without this, `task.value` would keep waiting for the inner
      // retry loop even after the caller cancels.
      try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
      }
    } catch {
      // If the subscribe attempt didn't transition us to .subscribed, make
      // sure external observers see .unsubscribed.
      if case .subscribing = state {
        joinRef = nil
        pushes = [:]
        updateState(.unsubscribed)
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
        logger?.debug(
          "Subscribe attempt \(attempts)/\(maxRetryAttempts) for channel '\(topic)'"
        )

        try await withTimeout(interval: timeoutInterval) { [self] in
          await Result { try await runOneSubscribeAttempt() }
        }.get()

        logger?.debug("Subscribe succeeded for channel '\(topic)'")
        return
      } catch is TimeoutError {
        logger?.debug(
          "Subscribe timed out for channel '\(topic)' (attempt \(attempts)/\(maxRetryAttempts))"
        )

        guard attempts < maxRetryAttempts else {
          logger?.error(
            "Failed to subscribe to channel '\(topic)' after \(maxRetryAttempts) attempts"
          )
          throw RealtimeError.maxRetryAttemptsReached
        }

        let delay = retryDelay(attempts)
        logger?.debug(
          "Retrying subscribe for '\(topic)' in \(String(format: "%.2f", delay))s"
        )

        do {
          try await _clock.sleep(for: delay)
          if !(await ensureSocketConnected()) {
            logger?.debug("Socket disconnected during retry delay for '\(topic)'")
            throw CancellationError()
          }
        } catch {
          throw CancellationError()
        }
      }
    }

    throw RealtimeError.maxRetryAttemptsReached
  }

  private func runOneSubscribeAttempt() async throws {
    guard await ensureSocketConnected() else {
      throw CancellationError()
    }

    let ref = makeRef()
    joinRef = ref
    let changes = clientChanges

    await joinOperation(ref, changes)

    for await observed in stateSubject.values {
      try Task.checkCancellation()
      switch observed {
      case .subscribed:
        return
      case .unsubscribed:
        // Channel was closed (by server or unsubscribe) while we were
        // waiting. Abort this attempt; the outer flow decides whether to
        // retry or propagate.
        throw CancellationError()
      case .subscribing, .unsubscribing:
        continue
      }
    }
    throw CancellationError()
  }

  private func beginUnsubscribe(waitForServerClose: Bool) async {
    logger?.debug("Beginning unsubscribe flow for channel '\(topic)'")
    let task = Task<Void, Never> { [weak self] in
      guard let self else { return }
      await self.runUnsubscribe(waitForServerClose: waitForServerClose)
    }
    updateState(.unsubscribing(task))
    await task.value
  }

  private func runUnsubscribe(waitForServerClose: Bool) async {
    // Send `phx_leave`. When `waitForServerClose` is true, wait (bounded by
    // `timeoutInterval`) for the server's `phx_close` to transition us to
    // `.unsubscribed` via `didReceiveClose()`. Otherwise transition
    // immediately — this is the fire-and-forget path used when we abort an
    // in-flight subscribe.
    await leaveOperation()

    if waitForServerClose {
      let stateSubject = self.stateSubject
      _ = try? await withTimeout(interval: timeoutInterval) {
        for await observed in stateSubject.values {
          if case .unsubscribed = observed { return }
        }
      }
    }

    joinRef = nil
    pushes = [:]
    if case .unsubscribing = state {
      updateState(.unsubscribed)
    }
  }

  private func updateState(_ newState: State) {
    logger?.debug("State transition for '\(topic)': \(state) → \(newState)")
    stateSubject.yield(newState)
    // Invoke the synchronous observer after the subject is updated so the
    // callback sees the new value via ``state`` as well.
    stateDidChange?(newState)
  }

  // MARK: - Defaults

  /// Default exponential-backoff retry delay with ±25% jitter, capped at 30s.
  static let defaultRetryDelay: RetryDelay = { attempt in
    let baseDelay: TimeInterval = 1.0
    let maxDelay: TimeInterval = 30.0
    let backoffMultiplier: Double = 2.0

    let exponentialDelay = baseDelay * pow(backoffMultiplier, Double(attempt - 1))
    let cappedDelay = min(exponentialDelay, maxDelay)

    let jitterRange = cappedDelay * 0.25
    let jitter = Double.random(in: -jitterRange...jitterRange)

    return max(0.1, cappedDelay + jitter)
  }
}
