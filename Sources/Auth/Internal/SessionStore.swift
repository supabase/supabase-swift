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
  /// Storage was not read yet, or the read failed and waits for a retry.
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
    /// Applied only while ``SessionStore/generation`` still equals `fromGeneration`.
    case refreshed(Session, fromGeneration: UInt64)
    /// Merged into the session that is current when the commit runs.
    case userUpdated(User, event: AuthChangeEvent)
    case signedOut(SignOutReason, event: AuthChangeEvent)
    /// Signs out with ``AuthChangeEvent/signedOut``, but only while the store holds the session
    /// whose refresh token is `refreshToken`, or holds none when `refreshToken` is `nil`.
    ///
    /// A request that failed because its session is gone must not sign out whoever signed in
    /// after the request went out. When the store holds another session, the commit changes
    /// nothing and does not throw.
    case invalidated(SignOutReason, refreshToken: String?)
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

  /// Grows by one on every state change. A refresh records it when it starts, so that its result
  /// applies only to the state it started from.
  private(set) var generation: UInt64 = 0

  private let storage: any AuthStorage
  private let key: String
  private let now: @Sendable () -> Date
  private let published: LockIsolated<Published>
  private var lastOperation: Task<Void, any Error>?

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

  /// A lossless stream of changes.
  ///
  /// The first element is ``AuthChangeEvent/initialSession`` with the status once storage was
  /// read. Every later element is one change, in the order the store applied it.
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
  ///   stale, and ``AuthError/sessionMissing`` for a `.userUpdated` transition while no user is
  ///   signed in.
  func commit(_ transition: Transition) async throws {
    try await serialized { try await self.apply(transition) }
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

    case .refreshed(let session, let fromGeneration):
      guard fromGeneration == generation else { throw AuthError.refreshDiscarded }
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
      guard currentStatus != .loading, currentSession?.refreshToken == refreshToken else {
        return
      }
      next = .signedOut(reason)
      event = .signedOut
    }

    if case .signedIn(let received) = next {
      try await storage.save(PersistedSessionCodec.encode(received), key: key)
    } else {
      try await storage.remove(key: key)
    }
    update(to: next, event: event)
  }

  private func update(to next: State, event: AuthChangeEvent) {
    generation += 1
    published.withValue { current in
      // A subscriber that joined while loading has seen nothing, so its first element is the
      // initial session even when a commit, not the load, ended loading.
      let change = AuthChange(
        event: current.state.status == .loading ? .initialSession : event,
        status: next.status
      )
      current.state = next
      for continuation in current.subscribers.values {
        continuation.yield(change)
      }
    }
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
