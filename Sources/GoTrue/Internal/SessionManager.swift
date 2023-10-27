import Foundation
import KeychainAccess
@_spi(Internal) import _Helpers

protocol SessionRefresher: AnyObject {
  func refreshSession(refreshToken: String) async throws -> Session
}

protocol SessionManager: Sendable {
  func session() async throws -> Session
  func update(_ session: Session) async throws
  func remove() async
}

actor DefaultSessionManager: SessionManager {
  private var task: Task<Session, Error>?

  private var storage: SessionStorage {
    Dependencies.current.value!.sessionStorage
  }

  private var sessionRefresher: SessionRefresher {
    Dependencies.current.value!.sessionRefresher
  }

  func session() async throws -> Session {
    if let task {
      return try await task.value
    }

    guard let currentSession = try storage.getSession() else {
      throw GoTrueError.sessionNotFound
    }

    if currentSession.isValid {
      return currentSession.session
    }

    task = Task {
      defer { task = nil }

      let session = try await sessionRefresher.refreshSession(
        refreshToken: currentSession.session.refreshToken)
      try update(session)
      return session
    }

    return try await task!.value
  }

  func update(_ session: Session) throws {
    try storage.storeSession(StoredSession(session: session))
  }

  func remove() {
    storage.deleteSession()
  }
}
