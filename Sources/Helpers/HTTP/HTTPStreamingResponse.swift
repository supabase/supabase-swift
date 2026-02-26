//
//  HTTPStreamingResponse.swift
//
//
//  Created by Claude Code on 26/02/26.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A streaming HTTP response that yields data chunks as they arrive.
///
/// Use this type for responses that need to be processed incrementally, such as:
/// - Server-Sent Events (SSE)
/// - Large file downloads
/// - Streaming APIs (like OpenAI, Anthropic)
///
/// Example:
/// ```swift
/// let streamingResponse = try await httpSession.sendStreaming(request)
/// for try await chunk in streamingResponse.stream {
///   // Process each chunk as it arrives
///   print("Received \(chunk.count) bytes")
/// }
/// ```
package struct HTTPStreamingResponse: Sendable {
  /// The HTTP response metadata (status code, headers, etc.).
  package let response: HTTPURLResponse

  /// An async stream that yields data chunks as they arrive from the server.
  package let stream: AsyncThrowingStream<Data, any Error>

  /// Internal reference to the URLSessionDataTask for cancellation.
  private let task: URLSessionDataTask?

  package init(
    response: HTTPURLResponse,
    stream: AsyncThrowingStream<Data, any Error>,
    task: URLSessionDataTask? = nil
  ) {
    self.response = response
    self.stream = stream
    self.task = task
  }

  /// Cancel the streaming response.
  ///
  /// This method cancels the underlying network task and terminates the stream.
  /// Any in-flight data may be lost.
  package func cancel() {
    task?.cancel()
  }
}
