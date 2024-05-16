import _Helpers
import Foundation

struct SessionRefresher: Sendable {
  var refreshSession: @Sendable (_ refreshToken: String) async throws -> Session
}

actor SessionManager {
  private var task: Task<Session, any Error>?
  private var autoRefreshTask: Task<Void, any Error>?

  private var storage: any AuthLocalStorage {
    Current.configuration.localStorage
  }

  private var sessionRefresher: SessionRefresher {
    Current.sessionRefresher
  }

  func scheduleSessionRefresh(_ session: Session) throws {
    if autoRefreshTask != nil {
      return
    }

    autoRefreshTask = Task {
      defer { autoRefreshTask = nil }

      guard let expiresAt = session.expiresAt else {
        return
      }
      let expiryDate = Date(timeIntervalSince1970: expiresAt)

      let timeIntervalToExpiry = expiryDate.timeIntervalSinceNow

      // if negative then token is expired and will refresh right away
      let timeIntervalToRefresh = max(timeIntervalToExpiry * 0.8, 0)

      try await Task.sleep(nanoseconds: UInt64(timeIntervalToRefresh * 1_000_000_000))
      let session = try await sessionRefresher.refreshSession(session.refreshToken)
    }
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
    try scheduleSessionRefresh(session)
  }

  func remove() {
    try? storage.deleteSession()
  }
}
