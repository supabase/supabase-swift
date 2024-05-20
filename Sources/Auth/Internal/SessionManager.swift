import _Helpers
import Foundation

actor SessionManager {
  private var task: Task<Session, any Error>?

  private var storage: any AuthLocalStorage {
    Current.configuration.localStorage
  }

  private var sessionRefresher: SessionRefresher {
    Current.sessionRefresher
  }

  func session() async throws -> Session {
    if let task {
      return try await task.value
    }

    task = Task {
      defer { task = nil }

      guard let currentSession = try storage.getSession() else {
        throw AuthError.sessionNotFound
      }

      if currentSession.session.isValid {
        return currentSession.session
      }

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
