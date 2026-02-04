//
//  HTTPClient.swift
//
//
//  Created by Guilherme Souza on 30/04/24.
//

import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

package protocol HTTPClientType: Sendable {
  func send(_ request: HTTPRequest) async throws -> HTTPResponse
  func sendStreaming(_ request: HTTPRequest) async throws -> HTTPResponse.Stream
}

package actor HTTPClient: HTTPClientType {
  let fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse)
  let interceptors: [any HTTPClientInterceptor]
  let sessionConfiguration: URLSessionConfiguration

  package init(
    fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse),
    interceptors: [any HTTPClientInterceptor],
    sessionConfiguration: URLSessionConfiguration = .default
  ) {
    self.fetch = fetch
    self.interceptors = interceptors
    self.sessionConfiguration = sessionConfiguration
  }

  package func send(_ request: HTTPRequest) async throws -> HTTPResponse {
    var next: @Sendable (HTTPRequest) async throws -> HTTPResponse = { _request in
      let urlRequest = _request.urlRequest
      let (data, response) = try await self.fetch(urlRequest)
      guard let httpURLResponse = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
      }
      return HTTPResponse(data: data, response: httpURLResponse)
    }

    for interceptor in interceptors.reversed() {
      let tmp = next
      next = {
        try await interceptor.intercept($0, next: tmp)
      }
    }

    return try await next(request)
  }

  package func sendStreaming(_ request: HTTPRequest) async throws -> HTTPResponse.Stream {
    // Apply request-phase interceptors (modify headers, log request start, etc.)
    var modifiedRequest = request
    for interceptor in interceptors {
      modifiedRequest = try await interceptor.interceptRequest(modifiedRequest)
    }

    let urlRequest = modifiedRequest.urlRequest
    let capturedInterceptors = interceptors
    let capturedSessionConfiguration = sessionConfiguration

    return try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<HTTPResponse.Stream, any Error>) in
      let delegate = StreamingResponseDelegate(
        request: modifiedRequest,
        interceptors: capturedInterceptors,
        continuation: continuation
      )

      let session = URLSession(
        configuration: capturedSessionConfiguration,
        delegate: delegate,
        delegateQueue: nil
      )

      let task = session.dataTask(with: urlRequest)
      delegate.setTask(task)
      task.resume()
    }
  }
}

package protocol HTTPClientInterceptor: Sendable {
  func intercept(
    _ request: HTTPRequest,
    next: @Sendable (HTTPRequest) async throws -> HTTPResponse
  ) async throws -> HTTPResponse

  /// Intercept only the request phase (before sending).
  /// Used for streaming requests where the response cannot be intercepted in the same way.
  /// Default implementation returns the request unmodified.
  func interceptRequest(_ request: HTTPRequest) async throws -> HTTPRequest

  /// Called when a streaming response completes (successfully or with error).
  /// Used for logging the completion of streaming requests.
  func onStreamingResponseComplete(_ request: HTTPRequest, error: (any Error)?) async
}

extension HTTPClientInterceptor {
  package func interceptRequest(_ request: HTTPRequest) async throws -> HTTPRequest {
    request
  }

  package func onStreamingResponseComplete(_ request: HTTPRequest, error: (any Error)?) async {
    // Default: no-op
  }
}

/// URLSession delegate for handling streaming responses.
final class StreamingResponseDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  private let request: HTTPRequest
  private let interceptors: [any HTTPClientInterceptor]
  private let responseContinuation: CheckedContinuation<HTTPResponse.Stream, any Error>
  private let lock = NSLock()

  private var task: URLSessionTask?
  private var dataContinuation: AsyncThrowingStream<Data, any Error>.Continuation?
  private var hasResumedResponseContinuation = false

  init(
    request: HTTPRequest,
    interceptors: [any HTTPClientInterceptor],
    continuation: CheckedContinuation<HTTPResponse.Stream, any Error>
  ) {
    self.request = request
    self.interceptors = interceptors
    self.responseContinuation = continuation
    super.init()
  }

  func setTask(_ task: URLSessionTask) {
    lock.lock()
    self.task = task
    lock.unlock()
  }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard let httpResponse = response as? HTTPURLResponse else {
      lock.lock()
      if !hasResumedResponseContinuation {
        hasResumedResponseContinuation = true
        lock.unlock()
        responseContinuation.resume(throwing: URLError(.badServerResponse))
      } else {
        lock.unlock()
      }
      completionHandler(.cancel)
      return
    }

    let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()

    lock.lock()
    dataContinuation = continuation
    hasResumedResponseContinuation = true
    lock.unlock()

    let capturedRequest = request
    let capturedInterceptors = interceptors

    continuation.onTermination = { [weak self] _ in
      guard let self else { return }
      self.lock.lock()
      let task = self.task
      self.lock.unlock()
      task?.cancel()

      // Notify interceptors of completion
      Task {
        for interceptor in capturedInterceptors {
          await interceptor.onStreamingResponseComplete(capturedRequest, error: nil)
        }
      }
    }

    let streamResponse = HTTPResponse.Stream(
      statusCode: httpResponse.statusCode,
      headers: HTTPFields(httpResponse.allHeaderFields as? [String: String] ?? [:]),
      underlyingResponse: httpResponse,
      body: stream
    )

    responseContinuation.resume(returning: streamResponse)
    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    lock.lock()
    let continuation = dataContinuation
    lock.unlock()
    continuation?.yield(data)
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
  ) {
    lock.lock()
    let continuation = dataContinuation
    let alreadyResumed = hasResumedResponseContinuation
    lock.unlock()

    if let error {
      if !alreadyResumed {
        lock.lock()
        hasResumedResponseContinuation = true
        lock.unlock()
        responseContinuation.resume(throwing: error)
      } else {
        continuation?.finish(throwing: error)
      }
    } else {
      continuation?.finish()
    }

    // Notify interceptors of completion
    let capturedRequest = request
    Task {
      for interceptor in interceptors {
        await interceptor.onStreamingResponseComplete(capturedRequest, error: error)
      }
    }
  }
}
