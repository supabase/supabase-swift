//
//  AccessTokenMiddleware.swift
//  Helpers
//
//  Created by Guilherme Souza on 06/10/26.
//

public import HTTPTypes

/// Resolves the current access token and sends it as `Authorization: Bearer`, unless the request
/// already carries `Authorization`. A per-call header therefore wins over the provider, and a
/// `nil` token leaves the header off.
///
/// `SupabaseClient` installs one for every sub-client. A standalone client adds it to its
/// `HTTPClientConfiguration`, which is the one place a token enters a request:
///
/// ```swift
/// let storage = StorageClient(
///   configuration: StorageClientConfiguration(
///     url: url,
///     headers: ["apikey": key],
///     http: HTTPClientConfiguration(
///       middlewares: [AccessTokenMiddleware { try await tokenProvider.current() }]
///     )
///   )
/// )
/// ```
///
/// The provider runs for every request, so a token that rotates is always current. An error it
/// throws fails that request and reaches the caller unchanged.
public struct AccessTokenMiddleware: ClientMiddleware {
  let getAccessToken: @Sendable () async throws -> String?

  /// - Parameter getAccessToken: Resolves the token to send, or `nil` to send none.
  public init(getAccessToken: @escaping @Sendable () async throws -> String?) {
    self.getAccessToken = getAccessToken
  }

  public func intercept(
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
