import Foundation

/// ``APIClient`` plus the session bookkeeping the user-facing client needs: the access token of
/// the stored session, and clearing that session when the server reports it is gone.
struct SessionAPIClient: Sendable {
  let api: APIClient
  let sessionManager: SessionManager
  let eventEmitter: AuthStateChangeEventEmitter

  /// Sends `request` and decodes its response.
  ///
  /// `ownership` names the stored session the request is issued for. A response saying that
  /// session is gone then only clears storage while ``SessionOwnership`` still covers what is
  /// stored, so a request that outlived a sign-out cannot sign out whoever signed in after it.
  /// Callers with no session of their own (sign-in, sign-up) leave the default, and their
  /// failures never clear storage: a banned user's sign-in attempt must not sign out whoever is
  /// signed in.
  func execute<Response>(
    _ request: AuthRequest<Response>, for ownership: SessionOwnership = .unscoped
  ) async throws -> Response {
    do {
      return try await api.execute(request)
    } catch let error as AuthError where error.invalidatesSession {
      if await sessionManager.removeIfUnchanged(ownership) {
        eventEmitter.emit(.signedOut, session: nil)
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
