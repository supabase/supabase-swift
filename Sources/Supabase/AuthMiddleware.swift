import Foundation
import HTTPTypes
import Helpers

struct AuthMiddleware: ClientMiddleware {
  let auth: AuthClient
  let fallbackToken: String?

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

    guard let usedToken = try await sessionAccessToken() else {
      return try await next(request.signed(with: fallbackToken), body)
    }

    let (response, responseBody) = try await next(request.signed(with: usedToken), body)
    guard response.status == .unauthorized, body?.iterationBehavior != .single,
      let retryToken = try await retryToken(after: usedToken)
    else {
      return (response, responseBody)
    }

    if let responseBody {
      _ = try? await Data(collecting: responseBody, upTo: 1 << 20)
    }
    return try await next(request.signed(with: retryToken), body)
  }

  private func sessionAccessToken() async throws -> String? {
    do {
      return try await auth.session.accessToken
    } catch let error as AuthError where error.kind == .sessionMissing {
      return nil
    }
  }

  private func retryToken(after usedToken: String) async throws -> String? {
    guard let current = auth.currentSession else { return nil }
    if current.accessToken != usedToken {
      return current.accessToken
    }
    do {
      return try await auth.refreshSession().accessToken
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
