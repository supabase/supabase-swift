import _Helpers
import Foundation

struct SessionRefresher: Sendable {
  var refreshSession: @Sendable (_ refreshToken: String) async throws -> Session
}

struct SessionManager: Sendable {
  var session: @Sendable (_ shouldValidateExpiration: Bool) async throws -> Session
  var update: @Sendable (_ session: Session) async throws -> Void
  var remove: @Sendable () async -> Void
  var refreshSession: @Sendable (_ refreshToken: String) async throws -> Session
}

extension SessionManager {
  func session(shouldValidateExpiration: Bool = true) async throws -> Session {
    try await session(shouldValidateExpiration)
  }
}

extension SessionManager {
  static let live: SessionManager = {
    let manager = _DefaultSessionManager()

    return SessionManager(
      session: { try await manager.session(shouldValidateExpiration: $0) },
      update: { try await manager.update($0) },
      remove: { await manager.remove() },
      refreshSession: { try await manager.refreshSession($0) }
    )
  }()
}

private actor _DefaultSessionManager {
  private var task: Task<Session, any Error>?

  @Dependency(\.sessionStorage)
  private var storage: SessionStorage

  @Dependency(\.sessionRefresher)
  private var sessionRefresher: SessionRefresher

  @Dependency(\.eventEmitter)
  private var eventEmitter: EventEmitter

  func session(shouldValidateExpiration: Bool) async throws -> Session {
    if let task {
      return try await task.value
    }

    guard let currentSession = try storage.getSession() else {
      throw AuthError.sessionNotFound
    }

    if currentSession.isValid || !shouldValidateExpiration {
      return currentSession.session
    }

    task = Task {
      defer { task = nil }

      return try await refreshSession(currentSession.session.refreshToken)
    }

    return try await task!.value
  }

  func update(_ session: Session) throws {
    try storage.storeSession(StoredSession(session: session))
    eventEmitter.emit(.tokenRefreshed, session: session)
  }

  func remove() {
    try? storage.deleteSession()
  }

  @discardableResult
  func refreshSession(_ refreshToken: String) async throws -> Session {
    let session = try await sessionRefresher.refreshSession(refreshToken)
    try update(session)
    return session
  }
}
