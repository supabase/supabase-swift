//
//  StreamingDelegate.swift
//
//
//  Created by Claude Code on 26/02/26.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// URLSessionDelegate for handling streaming responses.
///
/// This delegate yields data chunks to an AsyncThrowingStream as they arrive from the server.
/// It validates the response status code and handles errors appropriately.
package final class StreamingDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  private let stream: AsyncThrowingStream<Data, any Error>
  private let streamContinuation: AsyncThrowingStream<Data, any Error>.Continuation

  private let continuation: CheckedContinuation<HTTPStreamingResponse, any Error>

  private let lock = NSLock()
  private var hasResumedContinuation = false

  package init(continuation: CheckedContinuation<HTTPStreamingResponse, any Error>) {
    (stream, streamContinuation) = AsyncThrowingStream.makeStream()
    self.continuation = continuation
    super.init()
  }

  // MARK: - URLSessionDataDelegate

  package func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard let httpResponse = response as? HTTPURLResponse else {
      lock.withLock {
        guard !hasResumedContinuation else { return }
        hasResumedContinuation = true
        continuation.resume(throwing: URLError(.badServerResponse))
      }
      completionHandler(.cancel)
      return
    }

    // Validate status code (200-299)
    guard (200...299).contains(httpResponse.statusCode) else {
      let error = NSError(
        domain: "HTTPStreamingError",
        code: httpResponse.statusCode,
        userInfo: [
          NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)",
          "statusCode": httpResponse.statusCode,
        ]
      )
      lock.withLock {
        guard !hasResumedContinuation else { return }
        hasResumedContinuation = true
        continuation.resume(throwing: error)
      }
      completionHandler(.cancel)
      return
    }

    lock.withLock {
      guard !hasResumedContinuation else { return }
      hasResumedContinuation = true
      continuation.resume(
        returning: HTTPStreamingResponse(
          response: httpResponse,
          stream: stream,
          task: dataTask
        )
      )
    }
    completionHandler(.allow)
  }

  package func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive data: Data
  ) {
    // Yield data chunk to the stream
    streamContinuation.yield(data)
  }

  package func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    if let error = error {
      lock.withLock {
        guard !hasResumedContinuation else {
          // Already streaming - propagate error through stream
          streamContinuation.finish(throwing: error)
          return
        }
        // Not yet streaming - fail the initial call
        hasResumedContinuation = true
        continuation.resume(throwing: error)
      }
    } else {
      // Success - finish stream normally
      streamContinuation.finish()
    }
  }
}
