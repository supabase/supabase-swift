import _Helpers
import Foundation

struct SessionRefresher: Sendable {
  var refreshSession: @Sendable (_ refreshToken: String) async throws -> Session
}

actor SessionManager {
  private var task: Task<Session, any Error>?

  private let storage: any AuthLocalStorage
  private let sessionRefresher: SessionRefresher

  init(
    storage: any AuthLocalStorage,
    sessionRefresher: SessionRefresher
  ) {
    self.storage = storage
    self.sessionRefresher = sessionRefresher
  }

  func session(shouldValidateExpiration: Bool = true) async throws -> Session {
    if let task {
      return try await task.value
    }

    task = Task {
      defer { task = nil }

      guard let currentSession = try storage.getSession() else {
        throw AuthError.sessionNotFound
      }

      if currentSession.isValid || !shouldValidateExpiration {
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
