import Foundation
@_spi(Internal) import _Helpers

struct SessionRefresher: Sendable {
  var refreshSession: @Sendable (_ refreshToken: String) async throws -> Session
}

struct SessionManager: Sendable {
  var session: @Sendable (_ shouldValidateExpiration: Bool) async throws -> Session
  var update: @Sendable (_ session: Session) async throws -> Void
  var remove: @Sendable () async -> Void

  func session(shouldValidateExpiration: Bool = true) async throws -> Session {
    try await session(shouldValidateExpiration)
  }
}

extension SessionManager {
  static var live: Self = {
    let manager = _LiveSessionManager()
    return Self(
      session: { try await manager.session(shouldValidateExpiration: $0) },
      update: { try await manager.update($0) },
      remove: { await manager.remove() }
    )
  }()
}

actor _LiveSessionManager {
  private var task: Task<Session, Error>?

  private var storage: SessionStorage {
    Dependencies.current.value!.sessionStorage
  }

  private var sessionRefresher: SessionRefresher {
    Dependencies.current.value!.sessionRefresher
  }

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

      let session = try await sessionRefresher.refreshSession(currentSession.session.refreshToken)
      try update(session)
      return session
    }

    return try await task!.value
  }

  func update(_ session: Session) throws {
    try storage.storeSession(StoredSession(session: session))
  }

  func remove() {
    try? storage.deleteSession()
  }
}
