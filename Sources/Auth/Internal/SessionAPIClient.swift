import Foundation

/// Which session a request may sign out when the server says the session it was issued for is
/// gone.
enum SessionOwnership: Sendable {
  /// The request was issued for no particular session, such as sign-in or sign-up. A rejection
  /// of it says nothing about the current session, so it never signs out.
  case unscoped
  /// The session the request was issued for, read before the request went out; `nil` when no
  /// session was held then. A rejection signs out only while the store still holds exactly this,
  /// so a request that outlived a sign-out cannot sign out whoever signed in after it.
  case snapshot(Session?)
}

/// ``APIClient`` plus the session bookkeeping the user-facing client needs: the access token of
/// the current session, and signing out when the server reports that session is gone.
struct SessionAPIClient: Sendable {
  let api: APIClient
  let sessionManager: SessionManager
  let sessionStore: SessionStore

  /// Sends `request` and decodes its response.
  ///
  /// An error whose ``AuthError/invalidatesSession`` is `true` commits a sign-out to the store
  /// that applies only while the store holds the session `ownership` names. Callers with no
  /// session of their own (sign-in, sign-up) leave the default, and their failures never sign
  /// out: a banned user's sign-in attempt must not sign out whoever is signed in.
  func execute<Response>(
    _ request: AuthRequest<Response>, for ownership: SessionOwnership = .unscoped
  ) async throws -> Response {
    do {
      return try await api.execute(request)
    } catch let error as AuthError where error.invalidatesSession {
      if case .snapshot(let session) = ownership {
        try? await sessionStore.commit(
          .invalidated(SignOutReason(invalidatedBy: error), refreshToken: session?.refreshToken)
        )
      }
      throw error
    }
  }

  /// Sends the request `makeRequest` builds with the access token of the current session,
  /// refreshing the session first when it has expired.
  func authorizedExecute<Response>(
    _ makeRequest: (_ accessToken: String) throws -> AuthRequest<Response>
  ) async throws -> Response {
    let session = try await sessionManager.session()
    return try await execute(makeRequest(session.accessToken), for: .snapshot(session))
  }
}
