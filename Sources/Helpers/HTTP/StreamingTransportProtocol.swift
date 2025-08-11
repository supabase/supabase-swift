import Foundation
import HTTPTypes
import OpenAPIRuntime

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A transport protocol that supports streaming operations with progress tracking.
package protocol StreamingClientTransport: ClientTransport {
  /// Sends an HTTP request with streaming response and progress tracking.
  /// - Parameters:
  ///   - request: The HTTP request to send.
  ///   - body: The HTTP request body to send.
  ///   - baseURL: The base URL for the request.
  ///   - operationID: The operation identifier.
  ///   - progressHandler: A closure called with progress updates.
  /// - Returns: The HTTP response and an async stream of response data.
  func sendStreaming(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String,
    progressHandler: @escaping @Sendable (Progress) -> Void
  ) async throws -> (HTTPTypes.HTTPResponse, AsyncThrowingStream<Data, any Error>)
}