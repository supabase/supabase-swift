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

      if currentSession.isValid {
        return currentSession
      }

      return try await sessionRefresher.refreshSession(currentSession.refreshToken)
    }

    return try await task!.value
  }

  func update(_ session: Session) throws {
    try storage.storeSession(session)
  }

  func remove() {
    try? storage.deleteSession()
  }
}
