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
  private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
  private let lock = NSLock()
  private var response: URLResponse?

  package init(continuation: AsyncThrowingStream<Data, any Error>.Continuation) {
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
    lock.withLock {
      self.response = response
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      continuation.finish(throwing: URLError(.badServerResponse))
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
      continuation.finish(throwing: error)
      completionHandler(.cancel)
      return
    }

    completionHandler(.allow)
  }

  package func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive data: Data
  ) {
    // Yield data chunk to the stream
    continuation.yield(data)
  }

  package func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    if let error = error {
      // Handle cancellation separately
      if (error as NSError).code == NSURLErrorCancelled {
        continuation.finish(throwing: CancellationError())
      } else {
        continuation.finish(throwing: error)
      }
    } else {
      // Successfully completed
      continuation.finish()
    }
  }
}
