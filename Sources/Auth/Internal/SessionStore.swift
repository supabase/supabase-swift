//
//  SessionStore.swift
//  Auth
//
//  Created by Guilherme Souza on 26/10/26.
//

import ConcurrencyExtras
import Foundation

/// The one owner of the session.
///
/// Every change goes through ``commit(_:)``, which writes storage, then memory, then tells
/// subscribers. Operations run one at a time, in the order they reach the store, so storage,
/// memory, and the order of ``changes()`` always agree.
actor SessionStore {
  enum Transition: Sendable {
    case signedIn(Session, event: AuthEvent)
    /// Applied only while the store holds the session whose refresh token is `refreshToken`, or
    /// holds none when `refreshToken` is `nil`: what it held when the refresh started.
    ///
    /// A sign-in or sign-out while the request was out makes the result stale. A change that keeps
    /// the session, such as a user update, does not: the server already rotated the refresh token,
    /// so dropping the result would leave the store with a spent one.
    case refreshed(Session, replacing: String?)
    /// Merged into the session that is current when the commit runs.
    case userUpdated(User, event: AuthEvent)
    case signedOut(SignOutReason, event: AuthEvent)
    /// Signs out with ``AuthEvent/signedOut``, but only while the store holds the session
    /// whose refresh token is `refreshToken`.
    ///
    /// A request that failed because its session is gone must not sign out whoever signed in
    /// after the request went out. When the store holds another session or none, the commit
    /// changes nothing and does not throw.
    case invalidated(SignOutReason, refreshToken: String)
    /// Removes the identity `identityID` from the held user with ``AuthEvent/userUpdated``, but
    /// only while the held user is `userID`. Otherwise the commit changes nothing and does not
    /// throw, so a sign-out or sign-in that lands first keeps its own user.
    case identityUnlinked(UUID, userID: UUID)
    /// Stores the session from a verified email or phone change. The event is
    /// ``AuthEvent/userUpdated`` when the held user is the session's user, and
    /// ``AuthEvent/signedIn`` otherwise, because the change then signs that user in.
    case userChangeVerified(Session)
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

  private static let refreshFailureCooldown: TimeInterval = 60

  /// Grows by one on every state change, so tests can tell that a commit changed nothing, and the
  /// auto refresher can tell that the session changed after it was armed.
  private(set) var generation: UInt64 = 0

  /// Grows by one on every ``Transition/signedOut(_:event:)`` commit and every
  /// ``recordSignOut()``. A sign-in that started before
  /// a sign-out passes the count it read to ``commit(_:unlessSignedOutSince:)``.
  private(set) var signOuts: UInt64 = 0

  private let storage: any AuthStorage
  private let key: String
  private let now: @Sendable () -> Date
  private let published: LockIsolated<Published>
  private var lastOperation: Task<Void, any Error>?
  private var refreshFlights: [String: RefreshFlight] = [:]
  private var lastRefreshFailure: RefreshFailure?
  private var refreshWindow = RefreshWindow()
  private var autoRefreshDriver: Refresher.Driver?
  private var autoRefreshTask: Task<Void, Never>? {
    didSet { oldValue?.cancel() }
  }

  init(storage: any AuthStorage, key: String, now: @escaping @Sendable () -> Date = { Date() }) {
    self.storage = storage
    self.key = key
    self.now = now
    published = LockIsolated(Published())
  }

  /// Starts loaded with what `initialLoad`, a synchronous read of storage, returns. When it
  /// throws, the store starts ``AuthStatus/loading`` and ``load()`` reads storage again.
  init(
    storage: any AuthStorage,
    key: String,
    now: @escaping @Sendable () -> Date = { Date() },
    initialLoad: () throws -> ReceivedSession?
  ) {
    self.storage = storage
    self.key = key
    self.now = now
    let state: State
    if case .success(let loaded) = Result(catching: initialLoad) {
      state = loaded.map(State.signedIn) ?? .signedOut(.sessionMissing)
    } else {
      state = .loading
    }
    published = LockIsolated(Published(state: state))
  }

  deinit {
    autoRefreshTask?.cancel()
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
  /// The first element is ``AuthEvent/initialSession`` with the status once storage was
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

  /// Finishes every ``changes()`` stream, for a client that is released while a running task
  /// still holds the store.
  nonisolated func finishChanges() {
    let continuations = published.withValue { current in
      defer { current.subscribers = [:] }
      return current.subscribers.values
    }
    for continuation in continuations {
      continuation.finish()
    }
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
  /// - Throws: ``AuthError/refreshDiscarded`` for a `.refreshed` transition whose session is no
  ///   longer held, and ``AuthError/sessionMissing`` for a `.userUpdated` transition while no user is
  ///   signed in.
  func commit(_ transition: Transition) async throws {
    try await serialized { try await self.apply(transition) }
  }

  /// Counts a sign-out that found no session, without an event, so a sign-in that started before
  /// it cannot commit after it.
  func recordSignOut() async throws {
    try await serialized { await self.countSignOut() }
  }

  private func countSignOut() {
    signOuts += 1
  }

  /// Applies `transition` only when no sign-out was committed since `signOuts` was read.
  ///
  /// A sign-in that finishes after the user signed out must not sign them back in.
  ///
  /// - Throws: `CancellationError` when a sign-out came first, and changes nothing.
  func commit(_ transition: Transition, unlessSignedOutSince signOuts: UInt64) async throws {
    try await serialized {
      guard await self.signOuts == signOuts else { throw CancellationError() }
      try await self.apply(transition)
    }
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
      return try await cancellableValue(of: flight.task)
    }
    if let failure = lastRefreshFailure, failure.refreshToken == refreshToken,
      (0..<Self.refreshFailureCooldown).contains(now().timeIntervalSince(failure.date))
    {
      await signOutIfRejectedAndExpired(by: failure.error, refreshToken: refreshToken)
      throw failure.error
    }
    return try await cancellableValue(of: startRefresh(refreshToken, using: request))
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
    let heldRefreshToken = currentSession?.refreshToken
    let refreshesHeldSession = heldRefreshToken == refreshToken
    let heldUserAtStart = refreshesHeldSession ? currentSession?.user : nil
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

      try await serialized {
        try await self.applyRefreshed(
          session, replacing: heldRefreshToken, heldUserAtStart: heldUserAtStart)
      }
      return session
    }
    refreshFlights[refreshToken] = RefreshFlight(id: id, task: task)
    return task
  }

  /// Applies a refresh of the held session. A user update that committed while the request was out
  /// keeps its user: the server may have read the user before the update.
  private func applyRefreshed(
    _ session: Session, replacing heldRefreshToken: String?, heldUserAtStart: User?
  ) async throws {
    var session = session
    if let heldUserAtStart, let held = currentSession, held.refreshToken == heldRefreshToken,
      held.user != heldUserAtStart
    {
      session.user = held.user
    }
    try await apply(.refreshed(session, replacing: heldRefreshToken))
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

  func startAutoRefresh(using driver: Refresher.Driver) {
    autoRefreshDriver = driver
    armRefresher()
  }

  func stopAutoRefresh() {
    autoRefreshDriver = nil
    autoRefreshTask = nil
  }

  var isAutoRefreshStarted: Bool {
    autoRefreshDriver != nil
  }

  private func armRefresher() {
    guard let received = heldSession, let driver = autoRefreshDriver else {
      autoRefreshTask = nil
      return
    }
    let armedGeneration = generation
    let now = now
    autoRefreshTask = Task { [weak self] in
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
    _ = try await cancellableValue(of: flight)
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
    let event: AuthEvent
    switch transition {
    case .signedIn(let session, let signInEvent):
      next = .signedIn(ReceivedSession(session: session, receivedAt: now()))
      event = signInEvent

    case .refreshed(let session, let replacedRefreshToken):
      guard currentSession?.refreshToken == replacedRefreshToken else {
        throw AuthError.refreshDiscarded
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

    case .identityUnlinked(let identityID, let userID):
      guard case .signedIn(var current) = published.value.state, current.session.user.id == userID
      else { return }
      current.session.user.removeIdentity(identityID)
      next = .signedIn(current)
      event = .userUpdated

    case .userChangeVerified(let session):
      event = currentSession?.user.id == session.user.id ? .userUpdated : .signedIn
      next = .signedIn(ReceivedSession(session: session, receivedAt: now()))
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
      signOuts += 1
      for flight in refreshFlights.values {
        flight.task.cancel()
      }
      refreshFlights = [:]
    }
  }

  private func update(to next: State, event: AuthEvent) {
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

extension User {
  /// Removes the identity `identityID`, and its provider from `appMetadata["providers"]` when no
  /// other identity uses that provider.
  fileprivate mutating func removeIdentity(_ identityID: UUID) {
    guard let removed = identities?.first(where: { $0.id == identityID }) else { return }
    identities?.removeAll { $0.id == identityID }
    guard identities?.contains(where: { $0.provider == removed.provider }) != true,
      case .array(let providers) = appMetadata["providers"]
    else { return }
    appMetadata["providers"] = .array(providers.filter { $0 != .string(removed.provider.rawValue) })
  }
}
