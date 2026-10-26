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

/// Sends an ``AuthRequest`` and decodes its response.
///
/// Knows nothing about sessions. `AuthAdmin` uses it standalone; ``SessionAPIClient`` layers the
/// session bookkeeping on top for the user-facing client.
struct APIClient: Sendable {
  let http: HTTPClient

  func execute<Response>(_ request: AuthRequest<Response>) async throws -> Response {
    let response: HTTPResponse
    let data: Data
    do {
      (response, data) = try await http.send(request.head, body: request.body)
    } catch let urlError as URLError {
      throw AuthError(
        kind: .transport, message: urlError.localizedDescription, underlyingError: urlError)
    }

    return try request.decode(response, data)
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
