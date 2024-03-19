import Foundation
@_spi(Internal) import _Helpers

import Logging

struct SessionRefresher: Sendable {
  var refreshSession: @Sendable (_ refreshToken: String) async throws -> Session
}

protocol SessionManager: Sendable {
  func session(shouldValidateExpiration: Bool) async throws -> Session
  func update(_ session: Session) async throws -> Void
  func remove() async
}

extension SessionManager {
  func session() async throws -> Session {
    try await session(shouldValidateExpiration: true)
  }
}

actor DefaultSessionManager: SessionManager {
  static let shared = DefaultSessionManager()

  private init() {}

  private var task: Task<Session, any Error>?

  private var storage: SessionStorage {
    Dependencies.current.value!.sessionStorage
  }

  private var sessionRefresher: SessionRefresher {
    Dependencies.current.value!.sessionRefresher
  }
    
    let persistentLogger = Logging.Logger(label: Bundle.main.bundleIdentifier!)

  func session(shouldValidateExpiration: Bool) async throws -> Session {
    if let task {
      return try await task.value
    }

    guard let currentSession = try storage.getSession() else {
      throw AuthError.sessionNotFound
    }

      // persistentLogger.info("\(currentSession.expirationDate)")

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
      persistentLogger.info("Updating session")
    try storage.storeSession(StoredSession(session: session))
  }

  func remove() {
    try? storage.deleteSession()
  }
}
