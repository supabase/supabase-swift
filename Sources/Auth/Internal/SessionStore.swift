//
//  SessionStore.swift
//  Auth
//
//  Created by Guilherme Souza on 26/10/26.
//

import ConcurrencyExtras
import Foundation

/// Whether a user is signed in, as the client knows it in memory.
enum AuthStatus: Hashable, Sendable {
  /// Storage was not read yet, or it could not be read, for example because the device is locked
  /// before the first unlock. The next load reads it again.
  case loading
  case signedOut(SignOutReason)
  case signedIn(Session)

  var session: Session? {
    guard case .signedIn(let session) = self else { return nil }
    return session
  }
}

/// Why no user is signed in.
struct SignOutReason: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
  let rawValue: String

  init(rawValue: String) {
    self.rawValue = rawValue
  }

  init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// The app asked to sign out.
  static let userInitiated: SignOutReason = "userInitiated"
  /// The server reported that the session expired or that it no longer knows the refresh token.
  static let sessionExpired: SignOutReason = "sessionExpired"
  /// The server revoked the session: its refresh token was already used, the session is gone,
  /// or the user is banned.
  static let sessionRevoked: SignOutReason = "sessionRevoked"
  /// Storage held no usable session.
  static let sessionMissing: SignOutReason = "sessionMissing"

  /// The reason for an error whose ``AuthError/invalidatesSession`` is `true`.
  init(invalidatedBy error: AuthError) {
    switch error.errorCode {
    case .refreshTokenAlreadyUsed, .sessionNotFound, .userBanned:
      self = .sessionRevoked
    default:
      // refresh_token_not_found, session_expired, and an OAuth invalid_grant on refresh.
      self = .sessionExpired
    }
  }
}

/// One change of the auth status, delivered in the order the store applied it.
struct AuthChange: Hashable, Sendable {
  var event: AuthChangeEvent
  var status: AuthStatus
}

/// The one owner of the session.
///
/// Every change goes through ``commit(_:)``, which writes storage, then memory, then tells
/// subscribers. Operations run one at a time, in the order they reach the store, so storage,
/// memory, and the order of ``changes()`` always agree.
actor SessionStore {
  enum Transition: Sendable {
    case signedIn(Session, event: AuthChangeEvent)
    /// Applied while ``SessionStore/generation`` still equals `fromGeneration`, or while the store
    /// still holds the session whose refresh token is `redeemedRefreshToken`.
    ///
    /// The server has already rotated `redeemedRefreshToken`, so dropping the result would leave a
    /// held session whose next refresh redeems a used token. A commit that kept the token, such as
    /// a user update, keeps its user in the refreshed session.
    case refreshed(Session, redeemedRefreshToken: String, fromGeneration: UInt64)
    /// Merged into the session that is current when the commit runs.
    case userUpdated(User, event: AuthChangeEvent)
    case signedOut(SignOutReason, event: AuthChangeEvent)
    /// Signs out with ``AuthChangeEvent/signedOut``, but only while the store holds the session
    /// whose refresh token is `refreshToken`.
    ///
    /// A request that failed because its session is gone must not sign out whoever signed in
    /// after the request went out. When the store holds another session or none, the commit
    /// changes nothing and does not throw.
    case invalidated(SignOutReason, refreshToken: String)
  }

  private enum State {
    case loading
    case signedOut(SignOutReason)
    case signedIn(ReceivedSession)

    var status: AuthStatus {
      switch self {
      case .loading: .loading
      case .signedOut(let reason): .signedOut(reason)
      case .signedIn(let received): .signedIn(received.session)
      }
    }
  }

  private struct Published {
    var state = State.loading
    var subscribers: [UUID: AsyncStream<AuthChange>.Continuation] = [:]
  }

  private struct RefreshFlight {
    let id: UUID
    let task: Task<Session, any Error>
  }

  private struct RefreshFailure {
    let refreshToken: String
    let date: Date
    let error: any Error
  }

  private struct RefreshWindow {
    let interval: TimeInterval = 30
    let maximumAttempts = 5
    private var attempts: [Date] = []

    mutating func admit(at date: Date) -> Bool {
      attempts.removeAll { !(0..<interval).contains(date.timeIntervalSince($0)) }
      guard attempts.count < maximumAttempts else { return false }
      attempts.append(date)
      return true
    }
  }

  private enum Waiter {
    case pending
    case suspended(CheckedContinuation<Session, any Error>)
    case finished
  }

  private static let refreshFailureCooldown: TimeInterval = 60

  /// Grows by one on every state change. A refresh records it when it starts, so that its result
  /// applies only to the state it started from, or to a later state that still holds the redeemed
  /// refresh token.
  private(set) var generation: UInt64 = 0

  private let storage: any AuthStorage
  private let key: String
  private let now: @Sendable () -> Date
  private let published: LockIsolated<Published>
  private var lastOperation: Task<Void, any Error>?
  private var refreshFlights: [String: RefreshFlight] = [:]
  private var lastRefreshFailure: RefreshFailure?
  private var refreshWindow = RefreshWindow()
  private var refresher = Refresher()

  init(storage: any AuthStorage, key: String, now: @escaping @Sendable () -> Date = { Date() }) {
    self.storage = storage
    self.key = key
    self.now = now
    published = LockIsolated(Published())
  }

  /// Starts loaded with what a read of storage already returned: `loadedSession`, or no session
  /// when it is `nil`.
  init(
    storage: any AuthStorage,
    key: String,
    loadedSession: ReceivedSession?,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.storage = storage
    self.key = key
    self.now = now
    let state = loadedSession.map(State.signedIn) ?? .signedOut(.sessionMissing)
    published = LockIsolated(Published(state: state))
  }

  deinit {
    refresher.task?.cancel()
    for continuation in published.value.subscribers.values {
      continuation.finish()
    }
  }

  nonisolated var currentStatus: AuthStatus {
    published.value.state.status
  }

  nonisolated var currentSession: Session? {
    currentStatus.session
  }

  nonisolated func validSession(minimumValidity: Duration) -> Session? {
    guard let held = heldSession, !held.isExpired(at: now(), leeway: minimumValidity) else {
      return nil
    }
    return held.session
  }

  private nonisolated var heldSession: ReceivedSession? {
    guard case .signedIn(let received) = published.value.state else { return nil }
    return received
  }

  /// The number of live ``changes()`` streams, so tests can tell a released stream from a leak.
  nonisolated var subscriberCount: Int {
    published.value.subscribers.count
  }

  /// A lossless stream of changes.
  ///
  /// The first element is ``AuthChangeEvent/initialSession`` with the status once storage was
  /// read, or once a commit ended loading, in which case that commit's change follows it. Every
  /// later element is one change, in the order the store applied it.
  nonisolated func changes() -> AsyncStream<AuthChange> {
    let (stream, continuation) = AsyncStream<AuthChange>.makeStream(bufferingPolicy: .unbounded)
    let id = UUID()
    continuation.onTermination = { [published] _ in
      published.withValue { _ = $0.subscribers.removeValue(forKey: id) }
    }
    published.withValue { current in
      current.subscribers[id] = continuation
      if current.state.status != .loading {
        continuation.yield(AuthChange(event: .initialSession, status: current.state.status))
      }
    }
    return stream
  }

  /// Reads the stored session, migrating older formats, and leaves ``AuthStatus/loading``.
  ///
  /// Returns at once when storage was already read. A storage error keeps the status at
  /// ``AuthStatus/loading`` and propagates, so a later call retries. Data that does not decode
  /// is removed and the status becomes `.signedOut(.sessionMissing)`: retrying cannot repair it.
  func load() async throws {
    guard currentStatus == .loading else { return }
    try await serialized { try await self.loadIfNeeded() }
  }

  /// Applies `transition`: writes storage, updates memory, bumps ``generation``, and yields the
  /// change to every subscriber.
  ///
  /// When the storage write throws, the commit throws the same error and changes nothing.
  ///
  /// - Throws: ``AuthError/refreshDiscarded`` for a `.refreshed` transition whose generation is
  ///   stale while the store no longer holds the redeemed refresh token, and
  ///   ``AuthError/sessionMissing`` for a `.userUpdated` transition while no user is
  ///   signed in.
  func commit(_ transition: Transition) async throws {
    try await serialized { try await self.apply(transition) }
  }

  /// Redeems `refreshToken` once, however many callers ask at the same time, and commits the
  /// refreshed session.
  ///
  /// A caller that asks while a refresh of the same token runs waits for that refresh. A waiter
  /// whose task is cancelled throws `CancellationError` at once, and the refresh still commits.
  /// A ``Transition/signedOut(_:event:)`` commit cancels every running refresh.
  ///
  /// A failed refresh keeps the session, unless the server rejected `refreshToken` and the held
  /// session for it is expired. A fresh or a cached rejection then signs out before it throws.
  ///
  /// - Parameter request: Sends the refresh request. Called only when no refresh of
  ///   `refreshToken` runs.
  /// - Throws: The error of the last failed refresh, without a new request, when that refresh
  ///   redeemed `refreshToken` less than 60 seconds ago and no commit other than a
  ///   ``Transition/invalidated(_:refreshToken:)`` followed it.
  ///   ``AuthError/Kind-swift.struct/excessiveRefresh`` when five refreshes started in the last 30
  ///   seconds.
  func refresh(
    _ refreshToken: String,
    using request: @escaping @Sendable (_ refreshToken: String) async throws -> Session
  ) async throws -> Session {
    if let flight = refreshFlights[refreshToken] {
      return try await Self.value(of: flight.task)
    }
    if let failure = lastRefreshFailure, failure.refreshToken == refreshToken,
      (0..<Self.refreshFailureCooldown).contains(now().timeIntervalSince(failure.date))
    {
      await signOutIfRejectedAndExpired(by: failure.error, refreshToken: refreshToken)
      throw failure.error
    }
    return try await Self.value(of: startRefresh(refreshToken, using: request))
  }

  /// Refreshes the held session, whose refresh token was `refreshToken` when the caller read it,
  /// as ``refresh(_:using:)`` does.
  ///
  /// Sends only the refresh token the store holds now. When a commit replaced `refreshToken`
  /// after the caller's read, that commit redeemed or dropped it, so sending it again would reuse
  /// a rotated token. The store then returns the held session without a request while it is
  /// valid, and refreshes the held token when it is not.
  ///
  /// - Throws: ``AuthError/sessionMissing`` when the store holds no session.
  func refreshHeldSession(
    readWith refreshToken: String,
    using request: @escaping @Sendable (_ refreshToken: String) async throws -> Session
  ) async throws -> Session {
    guard let held = heldSession else { throw AuthError.sessionMissing }
    if held.session.refreshToken != refreshToken,
      !held.isExpired(at: now(), leeway: defaultExpiryMargin)
    {
      return held.session
    }
    return try await refresh(held.session.refreshToken, using: request)
  }

  private func startRefresh(
    _ refreshToken: String,
    using request: @escaping @Sendable (_ refreshToken: String) async throws -> Session
  ) throws -> Task<Session, any Error> {
    guard refreshWindow.admit(at: now()) else { throw AuthError.excessiveRefresh }

    let id = UUID()
    let fromGeneration = generation
    let refreshesHeldSession = currentSession?.refreshToken == refreshToken
    let task = Task {
      defer {
        if refreshFlights[refreshToken]?.id == id {
          refreshFlights[refreshToken] = nil
        }
      }

      let session: Session
      do {
        session = try await request(refreshToken)
      } catch {
        // Only a sign-out cancels a flight. A transport can report that cancel as another error,
        // such as `URLError.cancelled` from a response body.
        if Task.isCancelled { throw CancellationError() }
        if refreshesHeldSession {
          await signOutIfRejectedAndExpired(by: error, refreshToken: refreshToken)
        }
        if !(error is CancellationError) {
          lastRefreshFailure = RefreshFailure(refreshToken: refreshToken, date: now(), error: error)
        }
        throw error
      }

      try await commit(
        .refreshed(session, redeemedRefreshToken: refreshToken, fromGeneration: fromGeneration))
      return session
    }
    refreshFlights[refreshToken] = RefreshFlight(id: id, task: task)
    return task
  }

  private func signOutIfRejectedAndExpired(by error: any Error, refreshToken: String) async {
    guard let error = error as? AuthError, error.invalidatesSession else { return }
    if let held = heldSession, held.session.refreshToken == refreshToken,
      !held.isExpired(at: now(), leeway: defaultExpiryMargin)
    {
      return
    }
    try? await commit(
      .invalidated(SignOutReason(invalidatedBy: error), refreshToken: refreshToken))
  }

  func startAutoRefresh(for owner: UUID, using driver: Refresher.Driver) {
    refresher.add(driver, for: owner)
    armRefresher()
  }

  func stopAutoRefresh(for owner: UUID) {
    let wasDriving = refresher.activeOwner == owner
    refresher.remove(owner)
    if wasDriving {
      armRefresher()
    }
  }

  func isAutoRefreshStarted(by owner: UUID) -> Bool {
    refresher.isDriven(by: owner)
  }

  private func armRefresher() {
    guard let received = heldSession, let driver = refresher.activeDriver else {
      refresher.task = nil
      return
    }
    let armedGeneration = generation
    let now = now
    refresher.task = Task { [weak self] in
      await Refresher.run(for: received, driver: driver, now: now) {
        guard let self else { throw CancellationError() }
        try await self.refreshHeldSessionIgnoringCachedFailure(
          armedAt: armedGeneration, using: driver.request)
      }
    }
  }

  private func refreshHeldSessionIgnoringCachedFailure(
    armedAt armedGeneration: UInt64,
    using request: @escaping @Sendable (_ refreshToken: String) async throws -> Session
  ) async throws {
    guard generation == armedGeneration, let refreshToken = currentSession?.refreshToken else {
      throw CancellationError()
    }
    let flight =
      try refreshFlights[refreshToken]?.task ?? startRefresh(refreshToken, using: request)
    _ = try await Self.value(of: flight)
  }

  private static func value(of task: Task<Session, any Error>) async throws -> Session {
    let waiter = LockIsolated(Waiter.pending)
    let resume = { @Sendable (result: Result<Session, any Error>) in
      let continuation = waiter.withValue { state -> CheckedContinuation<Session, any Error>? in
        defer { state = .finished }
        guard case .suspended(let continuation) = state else { return nil }
        return continuation
      }
      continuation?.resume(with: result)
    }

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let cancelled = waiter.withValue { state in
          guard case .pending = state else { return true }
          state = .suspended(continuation)
          return false
        }
        if cancelled {
          continuation.resume(throwing: CancellationError())
          return
        }
        Task { resume(await task.result) }
      }
    } onCancel: {
      resume(.failure(CancellationError()))
    }
  }

  // Each operation runs in its own task, so cancelling the caller never stops a write halfway.
  private func serialized(_ operation: @escaping @Sendable () async throws -> Void) async throws {
    let previous = lastOperation
    let current = Task {
      _ = await previous?.result
      try await operation()
    }
    lastOperation = current
    try await current.value
  }

  private func loadIfNeeded() async throws {
    guard currentStatus == .loading else { return }
    let next: State
    do {
      if let received = try await PersistedSessionLoader.load(from: storage, key: key) {
        next = .signedIn(received)
      } else {
        next = .signedOut(.sessionMissing)
      }
    } catch is DecodingError {
      try await storage.remove(key: key)
      next = .signedOut(.sessionMissing)
    }
    update(to: next, event: .initialSession)
  }

  private func apply(_ transition: Transition) async throws {
    let next: State
    let event: AuthChangeEvent
    switch transition {
    case .signedIn(let session, let signInEvent):
      next = .signedIn(ReceivedSession(session: session, receivedAt: now()))
      event = signInEvent

    case .refreshed(var session, let redeemedRefreshToken, let fromGeneration):
      if fromGeneration != generation {
        guard let held = currentSession, held.refreshToken == redeemedRefreshToken else {
          throw AuthError.refreshDiscarded
        }
        session.user = held.user
      }
      next = .signedIn(ReceivedSession(session: session, receivedAt: now()))
      event = .tokenRefreshed

    case .userUpdated(let user, let userEvent):
      guard case .signedIn(var current) = published.value.state else {
        throw AuthError.sessionMissing
      }
      current.session.user = user
      next = .signedIn(current)
      event = userEvent

    case .signedOut(let reason, let signOutEvent):
      next = .signedOut(reason)
      event = signOutEvent

    case .invalidated(let reason, let refreshToken):
      guard currentSession?.refreshToken == refreshToken else { return }
      next = .signedOut(reason)
      event = .signedOut
    }

    if case .signedIn(let received) = next {
      try await storage.save(PersistedSessionCodec.encode(received), key: key)
    } else {
      try await storage.remove(key: key)
    }
    update(to: next, event: event)
    switch transition {
    case .invalidated:
      // The rejection that signed out stays cached, so a refresh of the dead token after the
      // sign-out throws it without a request.
      break
    default:
      lastRefreshFailure = nil
    }

    if case .signedOut = transition {
      for flight in refreshFlights.values {
        flight.task.cancel()
      }
      refreshFlights = [:]
    }
  }

  private func update(to next: State, event: AuthChangeEvent) {
    generation += 1
    published.withValue { current in
      var changes = [AuthChange(event: event, status: next.status)]
      // A subscriber that joined while loading has seen nothing, so it first gets the initial
      // session, even when a commit, not the load, ended loading. The commit's own event follows.
      if current.state.status == .loading, event != .initialSession {
        changes.insert(AuthChange(event: .initialSession, status: next.status), at: 0)
      }
      current.state = next
      for continuation in current.subscribers.values {
        for change in changes {
          continuation.yield(change)
        }
      }
    }
    armRefresher()
  }
}

extension SessionStore {
  /// Returns the live store for one project and storage key, creating it when none is alive.
  ///
  /// Two clients for one project share a store, so each sees the other's changes and they never
  /// redeem one refresh token twice. The registry holds stores weakly. The first caller's
  /// `storage` and `now` win: a later caller with the same `url` and `storageKey` gets the
  /// existing store, whatever storage it passes.
  ///
  /// - Parameter initialLoad: A synchronous read of storage, run only when this call creates the
  ///   store, so that the store starts loaded. When it throws, the store starts
  ///   ``AuthStatus/loading`` and ``load()`` reads storage again.
  static func shared(
    url: URL,
    storageKey: String,
    storage: any AuthStorage,
    now: @escaping @Sendable () -> Date = { Date() },
    initialLoad: (@Sendable () throws -> ReceivedSession?)? = nil
  ) -> SessionStore {
    registry.withValue { stores in
      let registryKey = RegistryKey(url: url, storageKey: storageKey)
      if let store = stores[registryKey]?.store {
        return store
      }
      let store: SessionStore
      if let initialLoad, case .success(let loaded) = Result(catching: initialLoad) {
        store = SessionStore(storage: storage, key: storageKey, loadedSession: loaded, now: now)
      } else {
        store = SessionStore(storage: storage, key: storageKey, now: now)
      }
      stores = stores.filter { $0.value.store != nil }
      stores[registryKey] = WeakStore(store: store)
      return store
    }
  }

  private struct RegistryKey: Hashable {
    var url: URL
    var storageKey: String
  }

  private struct WeakStore {
    weak var store: SessionStore?
  }

  private static let registry = LockIsolated<[RegistryKey: WeakStore]>([:])
}
