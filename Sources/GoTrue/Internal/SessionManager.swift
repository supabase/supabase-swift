import Foundation
import KeychainAccess

protocol SessionRefresher: AnyObject {
  func refreshSession(refreshToken: String) async throws -> Session
}

protocol SessionManager: Sendable {
  func setSessionRefresher(_ refresher: SessionRefresher?) async
  func session() async throws -> Session
  func update(_ session: Session) async throws
  func remove() async
}

actor DefaultSessionManager: SessionManager {
  private var task: Task<Session, Error>?
  private let storage: SessionStorage

  private weak var sessionRefresher: SessionRefresher?

  init(storage: SessionStorage) {
    self.storage = storage
  }

  func setSessionRefresher(_ refresher: SessionRefresher?) {
    sessionRefresher = refresher
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

      if let session = try await sessionRefresher?.refreshSession(
        refreshToken: currentSession.session.refreshToken)
      {
        try update(session)
        return session
      }

      throw GoTrueError.sessionNotFound
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
