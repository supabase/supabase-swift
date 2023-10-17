import Foundation
import KeychainAccess

struct StoredSession: Codable {
  var session: Session
  var expirationDate: Date

  var isValid: Bool {
    expirationDate > Date().addingTimeInterval(60)
  }

  init(session: Session, expirationDate: Date? = nil) {
    self.session = session
    self.expirationDate = expirationDate ?? Date().addingTimeInterval(session.expiresIn)
  }
}

actor SessionManager {
  typealias SessionRefresher = @Sendable (_ refreshToken: String) async throws -> Session

  private var task: Task<Session, Error>?
  private let localStorage: GoTrueLocalStorage
  private let sessionRefresher: SessionRefresher

  init(localStorage: GoTrueLocalStorage, sessionRefresher: @escaping SessionRefresher) {
    self.localStorage = localStorage
    self.sessionRefresher = sessionRefresher
  }

  func session() async throws -> Session {
    if let task {
      return try await task.value
    }

    guard let currentSession = try localStorage.getSession() else {
      throw GoTrueError.sessionNotFound
    }

    if currentSession.isValid {
      return currentSession.session
    }

    task = Task {
      defer { self.task = nil }

      let session = try await sessionRefresher(currentSession.session.refreshToken)
      try update(session)
      return session
    }

    return try await task!.value
  }

  func update(_ session: Session) throws {
    try localStorage.storeSession(StoredSession(session: session))
  }

  func remove() {
    localStorage.deleteSession()
  }
}

extension GoTrueLocalStorage {
  func getSession() throws -> StoredSession? {
    try retrieve(key: "supabase.session").flatMap {
      try JSONDecoder.goTrue.decode(StoredSession.self, from: $0)
    }
  }

  func storeSession(_ session: StoredSession) throws {
    try store(key: "supabase.session", value: JSONEncoder.goTrue.encode(session))
  }

  func deleteSession() {
    try? remove(key: "supabase.session")
  }
}
