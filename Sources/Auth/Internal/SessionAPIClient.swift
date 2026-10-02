import Foundation
import HTTPTypes

/// ``APIClient`` plus the session bookkeeping the user-facing client needs: `Authorization` from
/// the stored session, and clearing that session when the server reports it is gone.
struct SessionAPIClient: Sendable {
  let api: APIClient
  let sessionManager: SessionManager
  let eventEmitter: AuthStateChangeEventEmitter

  /// Sends `request` and returns the response body.
  ///
  /// `ownership` names the stored session the request is issued for. A response saying that
  /// session is gone then only clears storage while ``SessionOwnership`` still covers what is
  /// stored, so a request that outlived a sign-out cannot sign out whoever signed in after it.
  /// Callers with no session of their own (sign-in, sign-up, `/logout`) leave the default and
  /// keep the unconditional cleanup they have always had.
  func execute(
    _ request: HTTPRequest, body: Data? = nil, for ownership: SessionOwnership = .unscoped
  ) async throws -> Data {
    do {
      return try await api.execute(request, body: body)
    } catch let error as AuthError where error.invalidatesSession {
      // The check and the delete happen together inside the session manager's actor, so a
      // sign-in cannot land between them.
      if await sessionManager.removeIfUnchanged(ownership) {
        eventEmitter.emit(.signedOut, session: nil)
      }
      throw error
    }
  }

  @discardableResult
  func authorizedExecute(_ request: HTTPRequest, body: Data? = nil) async throws -> Data {
    let session = try await sessionManager.session()

    var request = request
    request.headerFields[.authorization] = "Bearer \(session.accessToken)"

    return try await execute(request, body: body, for: .snapshot(session))
  }
}
