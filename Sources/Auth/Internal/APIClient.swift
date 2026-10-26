import Foundation
import HTTPTypes
import Logging

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension HTTPClient {
  init(configuration: AuthClient.Configuration) {
    self.init(http: configuration.http, clock: configuration.clock, logger: configuration.logger)
  }

  init(http: HTTPClientConfiguration, clock: any Clock<Duration>, logger: Logging.Logger) {
    var policy = RetryPolicy.default
    policy.retryableMethods.formUnion([.post, .put, .delete])
    policy.retryableStatuses.remove(429)

    self.init(
      configuration: http,
      retrying: RetryRequestInterceptor(policy: policy, clock: clock),
      appending: [LoggerInterceptor(logger: logger)])
  }
}

/// Sends requests to the Auth server with the client's default headers and maps failures to
/// ``AuthError``.
///
/// Knows nothing about sessions. `AuthAdmin` uses it standalone; ``SessionAPIClient`` layers the
/// session bookkeeping on top for the user-facing client.
struct APIClient: Sendable {
  let headers: [String: String]
  let http: HTTPClient

  /// Sends `request` and returns the response body.
  func execute(_ request: HTTPRequest, body: Data? = nil) async throws -> Data {
    try await send(request, body: body).data
  }

  /// Like ``execute(_:body:)`` but also returns the response head, for callers that read headers.
  func send(
    _ request: HTTPRequest, body: Data? = nil
  ) async throws -> (response: HTTPResponse, data: Data) {
    var request = request
    request.headerFields = HTTPFields(headers).merging(with: request.headerFields)

    if request.headerFields[.apiVersionHeaderName] == nil {
      request.headerFields[.apiVersionHeaderName] = apiVersions[._20240101]!.name.rawValue
    }

    let response: HTTPResponse
    let data: Data
    do {
      (response, data) = try await http.send(request, body: body)
    } catch {
      guard let urlError = error as? URLError else { throw error }
      throw AuthError(
        kind: .transport, message: urlError.localizedDescription, underlyingError: urlError)
    }

    if let error = ErrorDecoder.error(response: response, data: data, request: request) {
      throw error
    }

    return (response, data)
  }
}

extension Data {
  /// Shadows `Data.decoded(as:decoder:)` from Helpers inside the Auth module so every existing
  /// decode call site throws ``AuthError`` with kind `.decoding` instead of a bare
  /// `DecodingError`. Same-module declarations win over imported ones with the same signature.
  func decoded<T: Decodable>(as _: T.Type = T.self, decoder: JSONDecoder = JSONDecoder()) throws
    -> T
  {
    do {
      return try decoder.decode(T.self, from: self)
    } catch {
      throw AuthError(
        kind: .decoding,
        message: "Failed to decode the Auth response as \(T.self).",
        underlyingError: error
      )
    }
  }
}
