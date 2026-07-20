//
//  HTTPTransport.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 08/07/26.
//
/// The abstraction generated clients depend on. Kept deliberately small so the
/// generated code never touches `URLSession` directly and so tests can inject a
/// mock transport.
package protocol HTTPTransport: Sendable {
  /// Buffered request/response.
  func send(_ request: HTTPRequest, uploadProgress: ProgressHandler?) async throws -> HTTPResponse

  /// Streaming response: head first, body as an async sequence of chunks.
  /// Used for large downloads and event streams.
  func stream(_ request: HTTPRequest) async throws -> HTTPResponseStream
}

extension HTTPTransport {
  package func send(_ request: HTTPRequest) async throws -> HTTPResponse {
    try await send(request, uploadProgress: nil)
  }
}
