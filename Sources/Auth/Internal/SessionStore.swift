//
//  SessionStore.swift
//  Auth
//
//  Created by Guilherme Souza on 26/10/26.
//

import ConcurrencyExtras
import Foundation
import Helpers

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
    /// A request that ended its session must not sign out whoever signed in after the request
    /// went out. When the store holds another session or none, the commit changes nothing and does
    /// not throw.
    case invalidated(SignOutReason, refreshToken: String)
    /// Signs out with ``AuthEvent/signedOut`` while the store holds the session whose refresh
    /// token was `refreshToken`, or a refresh of it, or holds none when `refreshToken` is `nil`.
    ///
    /// A server that ended a session also ended the refreshes of it, but not a session signed in
    /// after the request went out. Otherwise the commit changes nothing and does not throw.
    case revoked(SignOutReason, refreshToken: String?)
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
    /// An expired stored session that one refresh is trying to renew. The status is still
    /// ``AuthStatus/loading``, and no subscriber has heard of the session.
    case settling(Session)
    case signedOut(SignOutReason)
    case signedIn(Session)

    var status: AuthStatus {
      switch self {
      case .loading, .settling: .loading
      case .signedOut(let reason): .signedOut(reason)
      case .signedIn(let session): .signedIn(session)
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
    /// The reason of each caller that waits for the refresh, in the order they asked.
    var signOutReasons: [RejectionReason]
  }

  private struct RefreshFailure {
    let refreshToken: String
    let date: Date
    let error: any Error
  }

  private struct RefreshWindow {
    let interval: Duration = .seconds(30)
    let maximumAttempts = 5
    private var attempts: [Date] = []

    mutating func admit(at date: Date) -> Bool {
      attempts.removeAll {
        !(Duration.zero..<interval).contains(date.duration(since: $0))
      }
      guard attempts.count < maximumAttempts else { return false }
      attempts.append(date)
      return true
    }
  }

  private static let refreshFailureCooldown: Duration = .seconds(60)

  /// The one refresh that runs while an expired stored session is read, before the store leaves
  /// ``AuthStatus/loading``.
  struct StartupRefresh: Sendable {
    let request: @Sendable (_ refreshToken: String) async throws -> Session
    let clock: any Clock<Duration>
    let deadline: Duration
  }

  /// Why a rejected refresh of the held, expired session signs out, or `nil` to keep it.
  typealias RejectionReason = @Sendable (AuthError) -> SignOutReason?

  /// Signs out when the server rejected the session itself.
  static let rejectedSession: RejectionReason = {
    $0.invalidatesSession ? SignOutReason(invalidatedBy: $0) : nil
  }

  /// Grows by one on every state change, so tests can tell that a commit changed nothing, and the
  /// auto refresher can tell that the session changed after it was armed.
  private(set) var generation: UInt64 = 0

  /// Grows by one on every ``Transition/signedOut(_:event:)`` commit and every
  /// ``Transition/revoked(_:refreshToken:)`` commit that signs out. A sign-in that started before
  /// a sign-out passes the count it read to ``commit(_:unlessSignedOutSince:)``.
  private(set) var signOuts: UInt64 = 0

  private let storage: any AuthStorage
  private let key: String
  private let now: @Sendable () -> Date
  private let startupRefresh: StartupRefresh?
  private let published: LockIsolated<Published>
  private var lastOperation: Task<Void, any Error>?
  private var settling: Task<Void, any Error>?
  private var refreshFlights: [String: RefreshFlight] = [:]
  /// The refresh tokens that refreshes of the held session replaced since it was signed in.
  private var replacedRefreshTokens: Set<String> = []
  private var lastRefreshFailure: RefreshFailure?
  private var refreshWindow = RefreshWindow()
  private var autoRefreshDriver: Refresher.Driver?
  private var autoRefreshTask: Task<Void, Never>? {
    didSet { oldValue?.cancel() }
  }

  init(
    storage: any AuthStorage,
    key: String,
    now: @escaping @Sendable () -> Date,
    startupRefresh: StartupRefresh? = nil
  ) {
    self.storage = storage
    self.key = key
    self.now = now
    self.startupRefresh = startupRefresh
    published = LockIsolated(Published())
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
    guard let held, !held.isExpired(at: now(), leeway: minimumValidity) else {
      return nil
    }
    return held
  }

  /// The session the store holds, including an expired stored one that a startup refresh is
  /// renewing, which ``currentSession`` does not show while the status is ``AuthStatus/loading``.
  private nonisolated var held: Session? {
    switch published.value.state {
    case .signedIn(let session), .settling(let session): session
    case .loading, .signedOut: nil
    }
  }

  /// The number of callers that wait for the running refresh of `refreshToken`, so tests can tell
  /// that a caller joined it.
  func refreshCallerCount(for refreshToken: String) -> Int {
    refreshFlights[refreshToken]?.signOutReasons.count ?? 0
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
  ///
  /// An expired session that a ``StartupRefresh`` is set for stays ``AuthStatus/loading`` until
  /// one refresh of it ends or its deadline passes, and this waits for that. A refresh that is
  /// still running at the deadline keeps running, and commits as ``AuthEvent/tokenRefreshed``.
  func load() async throws {
    guard currentStatus == .loading else { return }
    try await serialized { try await self.loadIfNeeded() }
    if let settling {
      try await cancellableValue(of: settling)
    }
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

  /// Commits ``Transition/signedOut(_:event:)`` and returns the session it removed, read in the
  /// same operation, so no commit can land between the read and the sign-out.
  func signOut(_ reason: SignOutReason) async throws -> Session? {
    let removed = LockIsolated<Session?>(nil)
    try await serialized {
      removed.setValue(self.held)
      try await self.apply(.signedOut(reason, event: .signedOut))
    }
    return removed.value
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
  /// session for it is expired. A fresh or a cached rejection then signs out before it throws,
  /// unless storage holds a session with another refresh token: the store adopts that one.
  ///
  /// - Parameters:
  ///   - request: Sends the refresh request. Called only when no refresh of `refreshToken` runs.
  ///   - signOutReason: Why a rejection signs out, or `nil` to keep the session. Every caller of
  ///     one refresh gives a reason. The rejection signs out with ``SignOutReason/userInitiated``
  ///     when any of them gives it, and otherwise with the reason of the first caller that signs
  ///     out.
  /// - Throws: The error of the last failed refresh, without a new request, when that refresh
  ///   redeemed `refreshToken` less than 60 seconds ago and no commit other than a
  ///   ``Transition/invalidated(_:refreshToken:)`` followed it.
  ///   ``AuthError/Kind-swift.struct/excessiveRefresh`` when five refreshes started in the last 30
  ///   seconds.
  func refresh(
    _ refreshToken: String,
    using request: @escaping @Sendable (_ refreshToken: String) async throws -> Session,
    signOutReason: @escaping RejectionReason = rejectedSession
  ) async throws -> Session {
    if let flight = refreshFlights[refreshToken] {
      refreshFlights[refreshToken]?.signOutReasons.append(signOutReason)
      do {
        return try await cancellableValue(of: flight.task)
      } catch {
        await signOutIfRejectedAndExpired(
          by: error, refreshToken: refreshToken, reason: signOutReason)
        throw error
      }
    }
    if let failure = lastRefreshFailure, failure.refreshToken == refreshToken,
      (Duration.zero..<Self.refreshFailureCooldown).contains(
        now().duration(since: failure.date))
    {
      await signOutIfRejectedAndExpired(
        by: failure.error, refreshToken: refreshToken, reason: signOutReason)
      throw failure.error
    }
    return try await cancellableValue(
      of: startRefresh(refreshToken, using: request, signOutReason: signOutReason))
  }

  /// Refreshes the held session, whose refresh token was `refreshToken` when the caller read it,
  /// as ``refresh(_:using:signOutReason:)`` does.
  ///
  /// Sends only the refresh token the store holds now. When a commit replaced `refreshToken`
  /// after the caller's read, that commit redeemed or dropped it, so sending it again would reuse
  /// a rotated token. The store then returns the held session without a request while it is
  /// valid, and refreshes the held token when it is not.
  ///
  /// - Parameter requiringSameSession: Whether the held session must be the one the caller read,
  ///   or a refresh of it. A caller that acts on that one session, such as a sign-out, sets it, so
  ///   a sign-in that landed since never hands it another session.
  /// - Throws: ``AuthError/sessionMissing`` when the store holds no session, or another session
  ///   than the one the caller read while `requiringSameSession` is `true`.
  func refreshHeldSession(
    readWith refreshToken: String,
    requiringSameSession: Bool = false,
    using request: @escaping @Sendable (_ refreshToken: String) async throws -> Session,
    signOutReason: @escaping RejectionReason = rejectedSession
  ) async throws -> Session {
    guard let held else { throw AuthError.sessionMissing }
    if requiringSameSession, held.refreshToken != refreshToken,
      !replacedRefreshTokens.contains(refreshToken)
    {
      throw AuthError.sessionMissing
    }
    if held.refreshToken != refreshToken,
      !held.isExpired(at: now(), leeway: defaultExpiryMargin)
    {
      return held
    }
    return try await refresh(
      held.refreshToken, using: request, signOutReason: signOutReason)
  }

  private func startRefresh(
    _ refreshToken: String,
    using request: @escaping @Sendable (_ refreshToken: String) async throws -> Session,
    signOutReason: @escaping RejectionReason
  ) throws -> Task<Session, any Error> {
    guard refreshWindow.admit(at: now()) else { throw AuthError.excessiveRefresh }

    let id = UUID()
    let heldRefreshToken = held?.refreshToken
    let refreshesHeldSession = heldRefreshToken == refreshToken
    let heldUserAtStart = refreshesHeldSession ? held?.user : nil
    let task = Task {
      defer {
        if refreshFlights[refreshToken]?.id == id {
          refreshFlights[refreshToken] = nil
        }
      }

      let session: Session
      do {
        session = try await RefreshSignpost.interval { try await request(refreshToken) }
      } catch {
        // Only a sign-out cancels a flight. A transport can report that cancel as another error,
        // such as `URLError.cancelled` from a response body.
        if Task.isCancelled { throw CancellationError() }
        if refreshesHeldSession {
          let reasons = refreshFlights[refreshToken]?.signOutReasons ?? [signOutReason]
          await signOutIfRejectedAndExpired(
            by: error, refreshToken: refreshToken, reason: Self.combining(reasons))
        }
        if !(error is CancellationError) {
          lastRefreshFailure = RefreshFailure(refreshToken: refreshToken, date: now(), error: error)
        }
        throw error
      }

      do {
        try await serialized {
          try await self.applyRefreshed(
            session, replacing: heldRefreshToken, heldUserAtStart: heldUserAtStart)
        }
      } catch {
        if !(error is CancellationError) {
          lastRefreshFailure = RefreshFailure(refreshToken: refreshToken, date: now(), error: error)
        }
        throw error
      }
      return session
    }
    refreshFlights[refreshToken] = RefreshFlight(
      id: id, task: task, signOutReasons: [signOutReason])
    return task
  }

  /// Applies a refresh of the held session. A user update that committed while the request was out
  /// keeps its user: the server may have read the user before the update.
  private func applyRefreshed(
    _ session: Session, replacing heldRefreshToken: String?, heldUserAtStart: User?
  ) async throws {
    var session = session
    if let heldUserAtStart, let held, held.refreshToken == heldRefreshToken,
      held.user != heldUserAtStart
    {
      session.user = held.user
    }
    try await apply(.refreshed(session, replacing: heldRefreshToken))
  }

  /// Combines the reasons of the callers of one refresh. A sign-out that the user asked for
  /// names the cause better than the rejection does.
  private static func combining(_ reasons: [RejectionReason]) -> RejectionReason {
    { error in
      let candidates = reasons.compactMap { $0(error) }
      return candidates.contains(.userInitiated) ? .userInitiated : candidates.first
    }
  }

  private func signOutIfRejectedAndExpired(
    by error: any Error, refreshToken: String, reason: RejectionReason
  ) async {
    guard let error = error as? AuthError, let reason = reason(error) else { return }
    if let held, held.refreshToken == refreshToken,
      !held.isExpired(at: now(), leeway: defaultExpiryMargin)
    {
      return
    }
    try? await serialized {
      try await self.invalidateUnlessStorageHoldsANewerSession(reason, refreshToken: refreshToken)
    }
  }

  /// Another store over the same storage key may have redeemed `refreshToken` first and saved the
  /// session it got. Removing storage would sign that store out at the next launch, so when storage
  /// holds a session with another refresh token, this store adopts it instead of signing out.
  ///
  /// A storage read error changes nothing, as a failed write does. The rejection stays cached, so
  /// the next refresh of `refreshToken` tries the sign-out again.
  private func invalidateUnlessStorageHoldsANewerSession(
    _ reason: SignOutReason, refreshToken: String
  ) async throws {
    guard let held, held.refreshToken == refreshToken else { return }
    if let data = try await storage.load(key: key),
      let stored = try? PersistedSessionCodec.decode(data).session,
      stored.refreshToken != refreshToken
    {
      let sameUser = stored.user.id == held.user.id
      update(to: .signedIn(stored), event: startupEvent(sameUser ? .tokenRefreshed : .signedIn))
      if sameUser {
        replacedRefreshTokens.insert(refreshToken)
      } else {
        replacedRefreshTokens = []
      }
      return
    }
    try await apply(.invalidated(reason, refreshToken: refreshToken))
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
    guard case .signedIn(let session) = published.value.state, let driver = autoRefreshDriver
    else {
      autoRefreshTask = nil
      return
    }
    let armedGeneration = generation
    let now = now
    // A refresh of this token that failed a moment ago, as the startup one can, gets a backoff
    // before the next, not an immediate second request.
    let recentFailure = lastRefreshFailure.flatMap {
      $0.refreshToken == session.refreshToken
        && (Duration.zero..<Self.refreshFailureCooldown).contains(
          now().duration(since: $0.date))
        ? $0.error : nil
    }
    autoRefreshTask = Task.named("supabase.auth.refresher") { [weak self] in
      await Refresher.run(for: session, driver: driver, now: now, afterFailure: recentFailure) {
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
    guard generation == armedGeneration, let refreshToken = held?.refreshToken else {
      throw CancellationError()
    }
    let flight = try joinOrStartRefresh(of: refreshToken, using: request)
    _ = try await cancellableValue(of: flight)
  }

  /// The running refresh of `refreshToken`, or a new one that signs out on a rejection.
  private func joinOrStartRefresh(
    of refreshToken: String,
    using request: @escaping @Sendable (_ refreshToken: String) async throws -> Session
  ) throws -> Task<Session, any Error> {
    try refreshFlights[refreshToken]?.task
      ?? startRefresh(refreshToken, using: request, signOutReason: Self.rejectedSession)
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
    guard case .loading = published.value.state else { return }
    let next: State
    do {
      if let session = try await PersistedSessionLoader.load(from: storage, key: key) {
        next = .signedIn(session)
      } else {
        next = .signedOut(.sessionMissing)
      }
    } catch is DecodingError {
      try await storage.remove(key: key)
      next = .signedOut(.sessionMissing)
    }
    if case .signedIn(let session) = next, let startupRefresh,
      session.isExpired(at: now(), leeway: .zero)
    {
      published.withValue { $0.state = .settling(session) }
      // The refresh runs outside the serial queue: its commit is an operation of that queue.
      settling = Task { await self.settle(session, using: startupRefresh) }
    } else {
      update(to: next, event: .initialSession)
    }
  }

  /// Waits for the refresh of `session`, joining it when it runs, for at most the deadline, then
  /// leaves ``AuthStatus/loading`` unless that refresh already did. A deadline does not cancel
  /// the refresh.
  private func settle(_ session: Session, using startup: StartupRefresh) async {
    if let flight = try? joinOrStartRefresh(
      of: session.refreshToken, using: startup.request)
    {
      _ = try? await withTimeout(startup.deadline, clock: startup.clock) {
        try await cancellableValue(of: flight)
      }
    }
    try? await serialized { await self.finishSettling() }
    settling = nil
  }

  /// Delivers the stored session as it is, when no refresh or sign-out replaced it.
  private func finishSettling() {
    guard case .settling(let session) = published.value.state else { return }
    update(to: .signedIn(session), event: .initialSession)
  }

  /// A change that ends a startup refresh is the initial session, not a change that follows it.
  private func startupEvent(_ event: AuthEvent) -> AuthEvent {
    if case .settling = published.value.state { .initialSession } else { event }
  }

  private func apply(_ transition: Transition) async throws {
    let next: State
    let event: AuthEvent
    switch transition {
    case .signedIn(let session, let signInEvent):
      next = .signedIn(session)
      event = signInEvent

    case .refreshed(let session, let replacedRefreshToken):
      guard held?.refreshToken == replacedRefreshToken else {
        throw AuthError.refreshDiscarded
      }
      next = .signedIn(session)
      event = startupEvent(.tokenRefreshed)

    case .userUpdated(let user, let userEvent):
      guard case .signedIn(var current) = published.value.state else {
        throw AuthError.sessionMissing
      }
      current.user = user
      next = .signedIn(current)
      event = userEvent

    case .signedOut(let reason, let signOutEvent):
      next = .signedOut(reason)
      event = signOutEvent

    case .invalidated(let reason, let refreshToken):
      guard held?.refreshToken == refreshToken else { return }
      next = .signedOut(reason)
      event = startupEvent(.signedOut)

    case .revoked(let reason, let refreshToken):
      let heldRefreshToken = held?.refreshToken
      guard
        heldRefreshToken == refreshToken
          || refreshToken.map(replacedRefreshTokens.contains) == true
      else {
        return
      }
      next = .signedOut(reason)
      event = .signedOut

    case .identityUnlinked(let identityID, let userID):
      guard case .signedIn(var current) = published.value.state, current.user.id == userID
      else { return }
      current.user.removeIdentity(identityID)
      next = .signedIn(current)
      event = .userUpdated

    case .userChangeVerified(let session):
      event = held?.user.id == session.user.id ? .userUpdated : .signedIn
      next = .signedIn(session)
    }

    if case .signedIn(let session) = next {
      try await storage.save(PersistedSessionCodec.encode(session), key: key)
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
    switch transition {
    case .refreshed(_, let replacedRefreshToken):
      if let replacedRefreshToken { replacedRefreshTokens.insert(replacedRefreshToken) }
    case .userUpdated, .identityUnlinked:
      break
    default:
      replacedRefreshTokens = []
    }

    switch transition {
    case .signedOut, .revoked: signOuts += 1
    default: break
    }
    if case .signedOut = transition {
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
