//
//  AccessTokenMiddleware.swift
//  Helpers
//
//  Created by Guilherme Souza on 06/10/26.
//

package import HTTPTypes

/// Resolves the current access token and sends it as `Authorization: Bearer`, unless the request
/// already carries `Authorization`. A per-call header therefore wins over the provider, and a
/// `nil` token leaves the header off.
package struct AccessTokenMiddleware: ClientMiddleware {
  let getAccessToken: @Sendable () async throws -> String?

  package init(getAccessToken: @escaping @Sendable () async throws -> String?) {
    self.getAccessToken = getAccessToken
  }

  package func intercept(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    next:
      @Sendable (HTTPTypes.HTTPRequest, HTTPBody?) async throws -> (
        HTTPTypes.HTTPResponse, HTTPBody?
      )
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    var request = request
    if request.headerFields[.authorization] == nil, let token = try await getAccessToken() {
      request.headerFields[.authorization] = "Bearer \(token)"
    }
    return try await next(request, body)
  }
}
