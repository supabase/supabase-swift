import Foundation
import HTTPTypes
import Helpers

/// How a service rejects a request whose access token went stale.
enum StaleTokenRejection: Sendable {
  /// PostgREST and the Functions gateway answer 401.
  case unauthorized
  /// Storage answers 400, the same status it uses for an RLS denial and a missing object, so a
  /// 400 counts only when the token sent is past its `exp`.
  case badRequestWithExpiredToken

  func matches(_ status: HTTPResponse.Status, accessToken: String) -> Bool {
    switch self {
    case .unauthorized:
      status == .unauthorized
    case .badRequestWithExpiredToken:
      status == .badRequest && Self.isExpired(accessToken)
    }
  }

  private static func isExpired(_ accessToken: String) -> Bool {
    guard let exp = JWT.decodePayload(accessToken)?["exp"] as? TimeInterval else { return false }
    return Date(timeIntervalSince1970: exp) <= Date()
  }
}

struct AuthMiddleware: ClientMiddleware {
  let auth: AuthClient
  let fallbackToken: String?
  let staleTokenRejection: StaleTokenRejection

  func intercept(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    next:
      @Sendable (HTTPTypes.HTTPRequest, HTTPBody?) async throws -> (
        HTTPTypes.HTTPResponse, HTTPBody?
      )
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    guard request.headerFields[.authorization] == nil else {
      return try await next(request, body)
    }

    guard let used = try await signedInSession() else {
      return try await next(request.signed(with: fallbackToken), body)
    }

    let (response, responseBody) = try await next(request.signed(with: used.accessToken), body)
    guard body?.iterationBehavior != .single,
      staleTokenRejection.matches(response.status, accessToken: used.accessToken),
      let retry = try await retrySession(after: used)
    else {
      return (response, responseBody)
    }

    if let responseBody {
      _ = try? await Data(collecting: responseBody, upTo: 1 << 20)
    }
    return try await next(request.signed(with: retry.accessToken), body)
  }

  private func signedInSession() async throws -> Session? {
    do {
      return try await auth.session
    } catch let error as AuthError where error.kind == .sessionMissing {
      return nil
    }
  }

  private func retrySession(after used: Session) async throws -> Session? {
    guard let current = auth.currentSession else { return nil }
    let retry =
      current.accessToken == used.accessToken ? try await refreshedSession() : current
    return retry?.user.id == used.user.id ? retry : nil
  }

  private func refreshedSession() async throws -> Session? {
    do {
      return try await auth.refreshSession()
    } catch {
      try Task.checkCancellation()
      return nil
    }
  }
}

extension HTTPTypes.HTTPRequest {
  fileprivate func signed(with token: String?) -> Self {
    var request = self
    if let token {
      request.headerFields[.authorization] = "Bearer \(token)"
    }
    return request
  }
}
