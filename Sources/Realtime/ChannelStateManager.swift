import Foundation
import Logging

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

  /// Typed failure for a single subscribe attempt. These are lifecycle
  /// failures — not task cancellations — so the retry ladder treats them
  /// like timeouts and callers never see a spurious `CancellationError`
  /// (issue #1145, defect 2).
  enum SubscribeFailure: Error {
    /// The socket could not be connected (or reconnected) for this attempt.
    case socketNotConnected
    /// The channel transitioned to `.unsubscribed` while waiting for the
    /// join confirmation.
    case channelClosed
  }

  typealias MakeRef = @Sendable () -> String
  typealias EnsureSocketConnected = @Sendable () async -> Bool
  /// Synchronous socket-status probe. Unlike ``EnsureSocketConnected`` it
  /// never attempts to connect — used to decide whether `phx_leave` can be
  /// delivered at all.
  typealias IsSocketConnected = @Sendable () -> Bool
  typealias GetClientChanges = @Sendable () -> [PostgresJoinConfig]
  typealias JoinOperation =
    @Sendable (_ joinRef: String, _ clientChanges: [PostgresJoinConfig])
    async -> Void
  typealias LeaveOperation = @Sendable () async -> Void
  typealias RetryDelay = @Sendable (_ attempt: Int) -> Duration
  /// Synchronous callback invoked every time the state changes. The channel
  /// uses this to push status updates to observers without an async hop, so
  /// reading ``RealtimeChannelV2/status`` right after ``subscribe()`` returns
  /// sees the latest value.
  typealias StateDidChange = @Sendable (State) -> Void

  private(set) var state: State = .unsubscribed
  private var stateChangeContinuations: [(UUID, AsyncStream<State>.Continuation)] = []
  private let stateDidChange: StateDidChange?

  /// Publishes every state transition, replaying the current state to new
  /// subscribers. Reading from outside the actor crosses the actor boundary.
  var stateChanges: AsyncStream<State> {
    let id = UUID()
    let (stream, continuation) = AsyncStream<State>.makeStream(bufferingPolicy: .unbounded)
    stateChangeContinuations.append((id, continuation))

    continuation.onTermination = { [weak self] _ in
      Task { await self?.removeStateChangeContinuation(id) }
    }

    continuation.yield(state)

    return stream
  }

  private func removeStateChangeContinuation(_ id: UUID) {
    stateChangeContinuations.removeAll { $0.0 == id }
  }

  private(set) var joinRef: String?
  private var pushes: [String: PushV2] = [:]

  private let logger: Logging.Logger
  private let topic: String
  private let maxRetryAttempts: Int
  private let timeout: Duration
  private let clock: any Clock<Duration>

  private let makeRef: MakeRef
  private let ensureSocketConnected: EnsureSocketConnected
  private let isSocketConnected: IsSocketConnected
  private let getClientChanges: GetClientChanges
  private let joinOperation: JoinOperation
  private let leaveOperation: LeaveOperation
  private let retryDelay: RetryDelay

  private var closedByServerWhileSubscribing = false

  init(
    topic: String,
    logger: Logging.Logger,
    maxRetryAttempts: Int,
    timeout: Duration,
    clock: any Clock<Duration>,
    makeRef: @escaping MakeRef,
    ensureSocketConnected: @escaping EnsureSocketConnected,
    isSocketConnected: @escaping IsSocketConnected = { true },
    getClientChanges: @escaping GetClientChanges,
    joinOperation: @escaping JoinOperation,
    leaveOperation: @escaping LeaveOperation,
    retryDelay: @escaping RetryDelay = ChannelStateManager.defaultRetryDelay,
    stateDidChange: StateDidChange? = nil
  ) {
    self.topic = topic
    self.logger = logger
    self.maxRetryAttempts = maxRetryAttempts
    self.timeout = timeout
    self.clock = clock
    self.makeRef = makeRef
    self.ensureSocketConnected = ensureSocketConnected
    self.isSocketConnected = isSocketConnected
    self.getClientChanges = getClientChanges
    self.joinOperation = joinOperation
    self.leaveOperation = leaveOperation
    self.retryDelay = retryDelay
    self.stateDidChange = stateDidChange
  }

  /// Atomically register `push` under `ref` only if `joinRef` still matches
  /// the snapshot the caller captured when building the outgoing message.
  /// Returns `true` if the push was stored (caller should send the
  /// message); `false` if the state changed (caller should abandon it).
  func storePushIfJoinRefMatches(
    _ push: PushV2,
    ref: String,
    joinRef: String?
  ) -> Bool {
    guard self.joinRef == joinRef else { return false }
    pushes[ref] = push
    return true
  }

  func removePush(ref: String) -> PushV2? {
    pushes.removeValue(forKey: ref)
  }

  /// Drive the channel to ``State/subscribed``. Safe to call concurrently:
  /// the second caller waits for the first attempt to finish instead of
  /// starting a new one.
  func subscribe() async throws {
    switch state {
    case .subscribed:
      logger.debug("Subscribe no-op for channel '\(topic)': already subscribed")
      return

    case .subscribing(let task):
      logger.debug("Subscribe already in progress for channel '\(topic)', awaiting…")
      try await task.value
      return

    case .unsubscribing(let task):
      logger.debug("Waiting for in-flight unsubscribe on '\(topic)' before subscribing")
      await task.value
      try await subscribe()

    case .unsubscribed:
      try await beginSubscribe()
    }
  }

  /// Drive the channel to ``State/unsubscribed``. Cancels an in-flight
  /// subscribe if one is running.
  func unsubscribe() async {
    switch state {
    case .unsubscribed:
      logger.debug("Unsubscribe no-op for channel '\(topic)': already unsubscribed")
      return

    case .unsubscribing(let task):
      logger.debug("Unsubscribe already in progress for channel '\(topic)', awaiting…")
      await task.value
      return

    case .subscribing(let task):
      logger.debug("Cancelling in-flight subscribe to unsubscribe '\(topic)'")
      task.cancel()
      await beginUnsubscribe(waitForServerClose: false, sendLeave: isSocketConnected())

    case .subscribed:
      let socketConnected = isSocketConnected()
      await beginUnsubscribe(waitForServerClose: socketConnected, sendLeave: socketConnected)
    }
  }

  /// Reset channel state so it can rejoin after a reconnect.
  func resetForReconnect() {
    joinRef = nil
    pushes = [:]
    switch state {
    case .subscribed:
      updateState(.unsubscribed)
    case .subscribing(let task):
      task.cancel()
      updateState(.unsubscribed)
    case .unsubscribing:
      updateState(.unsubscribed)
    case .unsubscribed:
      break
    }
  }

  /// Called when the server confirms the `phx_join` (system.ok or phx_reply
  /// with `postgres_changes`).
  func didReceiveSubscribedOK() {
    guard case .subscribing = state else { return }
    logger.debug("Server confirmed subscribe for channel '\(topic)'")
    updateState(.subscribed)
  }

  /// Called when the server closes the channel (phx_close or system error
  /// that should drop the channel).
  ///
  /// Returns `true` if the close was applied; `false` if it belonged to a
  /// stale join and was ignored.
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
    pushes = [:]
    if case .subscribing(let task) = state {
      closedByServerWhileSubscribing = true
      task.cancel()
    }
    updateState(.unsubscribed)
    return true
  }

  private func beginSubscribe() async throws {
    logger.debug("Beginning subscribe flow for channel '\(topic)'")
    closedByServerWhileSubscribing = false
    let task = Task<Void, any Error> { [weak self] in
      guard let self else { return }
      try await self.runSubscribeAttempts()
    }
    updateState(.subscribing(task))

    do {
      try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
      }
    } catch {
      let closedByServer = closedByServerWhileSubscribing
      closedByServerWhileSubscribing = false

      if case .subscribing = state {
        joinRef = nil
        pushes = [:]
        updateState(.unsubscribed)
      }

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
        logger.debug(
          "Subscribe attempt \(attempts)/\(maxRetryAttempts) for channel '\(topic)'"
        )

        try await withTimeout(timeout, clock: clock) {
          [self] in try await runOneSubscribeAttempt()
        }

        logger.debug("Subscribe succeeded for channel '\(topic)'")
        return
      } catch let error where error is TimeoutError || error is SubscribeFailure {
        logger.debug(
          "Subscribe attempt failed for channel '\(topic)' (attempt \(attempts)/\(maxRetryAttempts)): \(error)"
        )

        guard attempts < maxRetryAttempts else {
          logger.error(
            "Failed to subscribe to channel '\(topic)' after \(maxRetryAttempts) attempts"
          )
          throw RealtimeError.maxRetryAttemptsReached
        }

        let delay = retryDelay(attempts)
        logger.debug(
          "Retrying subscribe for '\(topic)' in \(delay)"
        )

        try await clock.sleep(for: delay)
      }
    }

    throw RealtimeError.maxRetryAttemptsReached
  }

  private func runOneSubscribeAttempt() async throws {
    guard await ensureSocketConnected() else {
      throw SubscribeFailure.socketNotConnected
    }

    let ref = makeRef()
    joinRef = ref
    let changes = getClientChanges()

    await joinOperation(ref, changes)

    for await observed in stateChanges {
      try Task.checkCancellation()
      switch observed {
      case .subscribed:
        return
      case .unsubscribed:
        throw SubscribeFailure.channelClosed
      case .subscribing, .unsubscribing:
        continue
      }
    }
    throw SubscribeFailure.channelClosed
  }

  private func beginUnsubscribe(waitForServerClose: Bool, sendLeave: Bool) async {
    logger.debug("Beginning unsubscribe flow for channel '\(topic)'")
    let task = Task<Void, Never> { [weak self] in
      guard let self else { return }
      await self.runUnsubscribe(waitForServerClose: waitForServerClose, sendLeave: sendLeave)
    }
    updateState(.unsubscribing(task))
    await task.value
  }

  private func runUnsubscribe(waitForServerClose: Bool, sendLeave: Bool) async {
    if sendLeave {
      await leaveOperation()
    }

    if waitForServerClose {
      let stream = stateChanges
      _ = try? await withTimeout(timeout, clock: clock) {
        for await observed in stream {
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
    logger.debug("State transition for '\(topic)': \(state) → \(newState)")
    state = newState
    for (_, continuation) in stateChangeContinuations {
      continuation.yield(newState)
    }
    stateDidChange?(newState)
  }

  deinit {
    for (_, continuation) in stateChangeContinuations {
      continuation.finish()
    }
  }

  /// Default exponential-backoff retry delay with ±25% jitter, capped at 30s.
  static let defaultRetryDelay: RetryDelay = { attempt in
    let baseDelay: Double = 1.0
    let maxDelay: Double = 30.0
    let backoffMultiplier: Double = 2.0

    let exponentialDelay = baseDelay * pow(backoffMultiplier, Double(attempt - 1))
    let cappedDelay = min(exponentialDelay, maxDelay)

    let jitterRange = cappedDelay * 0.25
    let jitter = Double.random(in: -jitterRange...jitterRange)

    return .seconds(max(0.1, cappedDelay + jitter))
  }
}
