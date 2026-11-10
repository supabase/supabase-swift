//
//  AccessTokenMiddleware.swift
//  Helpers
//
//  Created by Guilherme Souza on 06/10/26.
//

import Foundation
public import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Resolves the current access token and sends it as `Authorization: Bearer`, unless the request
/// already carries `Authorization`. A static or per-call header therefore wins over the provider,
/// and a `nil` token leaves the header off.
///
/// For a standalone `PostgrestClient`, `StorageClient`, or `FunctionsClient`. `SupabaseClient`
/// installs its own middleware, which takes the token from its `AuthClient` session, or this
/// one around `SupabaseClient.Configuration.Auth.accessToken`. A standalone client adds this one
/// to its `HTTPClientConfiguration`, which is the one place a token enters a request:
///
/// ```swift
/// let storage = try StorageClient(
///   configuration: StorageClient.Configuration(
///     url: url,
///     headers: [.apikey: key],
///     http: HTTPClientConfiguration(
///       middlewares: [AccessTokenMiddleware { try await tokenProvider.current() }]
///     )
///   )
/// )
/// ```
///
/// The provider runs for every request attempt, so a token that rotates is always current, and a
/// retried request gets a fresh token. An error it throws fails that request: the client throws
/// its own error with kind `accessToken`, and the provider's error as `underlyingError`. A
/// `CancellationError` propagates as itself.
///
/// Do not add it to the `http` of `AuthClient`, `AuthAdminClient`, or `RealtimeClient`; each
/// reports an issue when it finds one. Auth sends its own tokens, and Realtime takes its token
/// from `RealtimeClient.Configuration.accessToken` for both the socket and `httpSend`.
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
    if request.headerFields[.authorization] == nil,
      let token = try await AccessTokenFailure.wrapping(getAccessToken)
    {
      request.headerFields[.authorization] = "Bearer \(token)"
    }
    return try await next(request, body)
  }
}

/// A token provider failed, so the request was not sent.
///
/// Thrown by ``AccessTokenMiddleware`` and by `SupabaseClient`'s Auth middleware. Each module maps
/// it to its own error with kind `accessToken`. A caller's own middleware, or a client that does
/// not map it, sees this type; its descriptions are the provider error's, so logs stay readable.
package struct AccessTokenFailure: Error, CustomStringConvertible, LocalizedError {
  /// The message each module's `accessToken` error carries.
  package static let message = "The access token provider failed, so the request was not sent."

  /// The provider's error.
  package let underlyingError: any Error

  package init(underlyingError: any Error) {
    self.underlyingError = underlyingError
  }

  package var description: String { String(describing: underlyingError) }

  package var errorDescription: String? { underlyingError.localizedDescription }

  /// Runs `provider`, wrapping any error it throws except a cancellation: `CancellationError`, or
  /// a `URLError(.cancelled)` from a cancelled task, which `URLSession` throws in its place.
  package static func wrapping<T>(_ provider: () async throws -> T) async throws -> T {
    do {
      return try await provider()
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
      throw CancellationError()
    } catch {
      throw AccessTokenFailure(underlyingError: error)
    }
  }
}

extension HTTPClientConfiguration {
  /// Whether ``middlewares`` holds an ``AccessTokenMiddleware``. Auth and Realtime report an
  /// issue when it does: their errors do not map its failure, and Realtime has its own token.
  package var containsAccessTokenMiddleware: Bool {
    middlewares.contains { $0 is AccessTokenMiddleware }
  }
}
