import Foundation
import HTTPTypes
import Helpers

/// How a service tells that it rejected the access token itself, not the request. A response
/// counts only when the service says so, so an app's own 401 or an RLS denial is never retried.
enum StaleTokenRejection: Sendable {
  /// PostgREST answers 401 with `WWW-Authenticate: Bearer error="invalid_token"` (RFC 6750) for
  /// every JWT it cannot accept. Its other 401s send no `error`.
  case postgrest
  /// The Edge Functions gateway answers 401 with an `sb-error-code` for a JWT it could not
  /// verify. A 401 from the function's own code carries none of these codes.
  case functions
  /// Storage answers 400 with code `AccessDenied` for both an expired JWT and an RLS denial, so
  /// only the message tells them apart. A 400 with no body is never a rejection.
  case storage

  /// Whether `response` rejects the access token, and the body to pass on in place of `body`.
  func inspect(
    _ response: HTTPResponse,
    body: HTTPBody?
  ) async throws -> (rejectsToken: Bool, body: HTTPBody?) {
    switch self {
    case .postgrest:
      let challenge = response.headerFields[.wwwAuthenticate] ?? ""
      return (
        response.status == .unauthorized && challenge.contains(#"error="invalid_token""#), body
      )
    case .functions:
      let code = response.headerFields[.sbErrorCode].map(FunctionsError.Code.init(rawValue:))
      return (response.status == .unauthorized && Self.functionsJWTCodes.contains(code), body)
    case .storage:
      guard response.status == .badRequest, let body else { return (false, body) }
      let data = try await Data(collecting: body, upTo: .max)
      let error = try? JSONDecoder().decode(StorageErrorBody.self, from: data)
      let rejectsToken =
        error?.code == StorageError.Code.accessDenied.rawValue
        && error.flatMap(\.message).map(Self.storageExpiredJWTMessages.contains) == true
      return (rejectsToken, HTTPBody(data))
    }
  }

  /// `UNAUTHORIZED_JWT` is the local CLI gateway's name for `UNAUTHORIZED_LEGACY_JWT`.
  private static let functionsJWTCodes: Set<FunctionsError.Code?> = [
    .unauthorizedLegacyJWT, .unauthorizedAsymmetricJWT, "UNAUTHORIZED_JWT",
  ]

  /// The message Storage sends since its April 2025 JWT library change, then the one before it.
  private static let storageExpiredJWTMessages: Set<String> = [
    #""exp" claim timestamp check failed"#, "jwt expired",
  ]

  private struct StorageErrorBody: Decodable {
    let code: String?
    let message: String?
  }
}

struct AuthMiddleware: ClientMiddleware {
  let auth: AuthClient
  let fallbackToken: String?
  let staleTokenRejection: StaleTokenRejection
  /// Under ``AuthClient/AutoRefreshPolicy/disabled`` another process owns the refresh, so a
  /// rejection is retried only with a newer stored token, never after a refresh.
  let autoRefresh: AuthClient.AutoRefreshPolicy

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

    let (response, sentBody) = try await next(request.signed(with: used.accessToken), body)
    guard body?.iterationBehavior != .single else { return (response, sentBody) }
    let (rejectsToken, responseBody) = try await staleTokenRejection.inspect(
      response, body: sentBody)
    guard rejectsToken, let retry = try await retrySession(after: used) else {
      return (response, responseBody)
    }

    if let responseBody {
      _ = try? await Data(collecting: responseBody, upTo: 1 << 20)
    }
    return try await next(request.signed(with: retry.accessToken), body)
  }

  private func signedInSession() async throws -> Session? {
    do {
      return try await auth.session()
    } catch let error as AuthError where error.kind == .sessionMissing {
      return nil
    }
  }

  private func retrySession(after used: Session) async throws -> Session? {
    let current = auth.currentSession
    let retry =
      current?.accessToken == used.accessToken ? try await refreshedSession() : current
    return retry?.user.id == used.user.id ? retry : nil
  }

  private func refreshedSession() async throws -> Session? {
    guard autoRefresh != .disabled else { return nil }
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
