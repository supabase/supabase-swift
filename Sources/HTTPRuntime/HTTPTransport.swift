//
//  HTTPTransport.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 08/07/26.
//

package import HTTPTypes

/// The abstraction generated clients depend on. Kept deliberately small so the
/// generated code never touches `URLSession` directly and so tests can inject a
/// mock transport.
package protocol HTTPTransport: Sendable {
  /// Buffered request/response.
  func send(
    _ request: HTTPRequest,
    body: HTTPBody?,
    uploadProgress: ProgressHandler?
  ) async throws(HTTPRuntimeError) -> HTTPBufferedResponse

  /// Streaming response: head first, body as an async sequence of chunks.
  /// Used for large downloads and event streams.
  func stream(_ request: HTTPRequest, body: HTTPBody?) async throws(HTTPRuntimeError)
    -> HTTPStreamedResponse
}

extension HTTPTransport {
  package func send(
    _ request: HTTPRequest,
    body: HTTPBody? = nil
  ) async throws(HTTPRuntimeError) -> HTTPBufferedResponse {
    try await send(request, body: body, uploadProgress: nil)
  }
}
