//
//  HTTPClient.swift
//
//
//  Created by Guilherme Souza on 30/04/24.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

package protocol HTTPClientType: Sendable {
  func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

package actor HTTPClient: HTTPClientType, HTTPSession {
  let fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse)
  let interceptors: [any HTTPClientInterceptor]
  let session: URLSession

  package init(
    fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse),
    interceptors: [any HTTPClientInterceptor],
    session: URLSession = .shared
  ) {
    self.fetch = fetch
    self.interceptors = interceptors
    self.session = session
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

  // MARK: - HTTPSession Conformance

  package func sendStreaming(_ request: HTTPRequest) async throws -> HTTPStreamingResponse {
    let urlRequest = request.urlRequest

    let (stream, streamContinuation) = AsyncThrowingStream<Data, any Error>.makeStream()

    let delegate = StreamingDelegate(continuation: streamContinuation)
    let delegateSession = URLSession(
      configuration: session.configuration, delegate: delegate, delegateQueue: nil)
    let task = delegateSession.dataTask(with: urlRequest)

    task.resume()

    // Wait for the first response (will be validated in delegate)
    // We need to create a temporary response object
    // The actual response validation happens in the delegate's didReceive response callback
    let placeholderResponse = HTTPURLResponse(
      url: urlRequest.url!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: nil
    )!

    return HTTPStreamingResponse(
      response: placeholderResponse,
      stream: stream,
      task: task
    )
  }

  package func upload(
    _ request: HTTPRequest,
    from data: Data,
    progress: (@Sendable (Int64, Int64) -> Void)?
  ) async throws -> HTTPResponse {
    let urlRequest = request.urlRequest

    if let progressHandler = progress {
      let (responseData, response) = try await withCheckedThrowingContinuation { continuation in
        let delegate = ProgressDelegate(progressHandler: progressHandler, completion: continuation)
        let delegateSession = URLSession(
          configuration: session.configuration, delegate: delegate, delegateQueue: nil)
        let task = delegateSession.uploadTask(with: urlRequest, from: data)
        task.resume()
      }
      guard let httpURLResponse = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
      }
      return HTTPResponse(data: responseData, response: httpURLResponse)
    } else {
      // No progress tracking, use standard fetch
      let (responseData, response) = try await session.upload(for: urlRequest, from: data)
      guard let httpURLResponse = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
      }
      return HTTPResponse(data: responseData, response: httpURLResponse)
    }
  }

  package func upload(
    _ request: HTTPRequest,
    fromFile fileURL: URL,
    progress: (@Sendable (Int64, Int64) -> Void)?
  ) async throws -> HTTPResponse {
    let urlRequest = request.urlRequest

    if let progressHandler = progress {
      let (responseData, response) = try await withCheckedThrowingContinuation { continuation in
        let delegate = ProgressDelegate(progressHandler: progressHandler, completion: continuation)
        let delegateSession = URLSession(
          configuration: session.configuration, delegate: delegate, delegateQueue: nil)
        let task = delegateSession.uploadTask(with: urlRequest, fromFile: fileURL)
        task.resume()
      }
      guard let httpURLResponse = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
      }
      return HTTPResponse(data: responseData, response: httpURLResponse)
    } else {
      // No progress tracking, use standard fetch
      let (responseData, response) = try await session.upload(for: urlRequest, fromFile: fileURL)
      guard let httpURLResponse = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
      }
      return HTTPResponse(data: responseData, response: httpURLResponse)
    }
  }

  package func download(
    _ request: HTTPRequest,
    progress: (@Sendable (Int64, Int64) -> Void)?
  ) async throws -> HTTPDownloadResponse {
    let urlRequest = request.urlRequest

    if let progressHandler = progress {
      let (data, response) = try await withCheckedThrowingContinuation { continuation in
        let delegate = ProgressDelegate(progressHandler: progressHandler, completion: continuation)
        let delegateSession = URLSession(
          configuration: session.configuration, delegate: delegate, delegateQueue: nil)
        let task = delegateSession.dataTask(with: urlRequest)
        task.resume()
      }

      guard let httpURLResponse = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
      }

      return HTTPDownloadResponse(
        data: data,
        response: httpURLResponse,
        bytesReceived: Int64(data.count)
      )
    } else {
      // No progress tracking, use standard fetch
      let (data, response) = try await session.data(for: urlRequest)
      guard let httpURLResponse = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
      }

      return HTTPDownloadResponse(
        data: data,
        response: httpURLResponse,
        bytesReceived: Int64(data.count)
      )
    }
  }

  #if !os(Linux) && !os(Windows) && !os(Android)
    @available(macOS 11.0, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    package func uploadInBackground(
      _ request: HTTPRequest,
      fromFile fileURL: URL,
      sessionIdentifier: String
    ) async throws -> HTTPBackgroundTask {
      let urlRequest = request.urlRequest

      let configuration = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
      configuration.isDiscretionary = false
      configuration.sessionSendsLaunchEvents = true

      let delegate = BackgroundDelegate()

      let backgroundSession = URLSession(
        configuration: configuration, delegate: delegate, delegateQueue: nil)
      let task = backgroundSession.uploadTask(with: urlRequest, fromFile: fileURL)

      let (_, progressContinuation) = AsyncStream<(bytesTransferred: Int64, totalBytes: Int64)>
        .makeStream()

      let completionTask = Task<HTTPResponse, any Error> {
        try await withCheckedThrowingContinuation { continuation in
          delegate.setHandlers(
            progressContinuation: progressContinuation,
            completionHandler: { response in
              continuation.resume(returning: response)
            },
            errorHandler: { error in
              continuation.resume(throwing: error)
            }
          )
        }
      }

      task.resume()

      return HTTPBackgroundTask(
        taskIdentifier: task.taskIdentifier,
        sessionIdentifier: sessionIdentifier,
        urlSessionTask: task,
        progressContinuation: progressContinuation,
        completionTask: completionTask
      )
    }

    @available(macOS 11.0, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    package func downloadInBackground(
      _ request: HTTPRequest,
      toFile fileURL: URL,
      sessionIdentifier: String
    ) async throws -> HTTPBackgroundTask {
      let urlRequest = request.urlRequest

      let configuration = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
      configuration.isDiscretionary = false
      configuration.sessionSendsLaunchEvents = true

      let delegate = BackgroundDelegate()

      let backgroundSession = URLSession(
        configuration: configuration, delegate: delegate, delegateQueue: nil)
      let task = backgroundSession.downloadTask(with: urlRequest)

      let (_, progressContinuation) = AsyncStream<(bytesTransferred: Int64, totalBytes: Int64)>
        .makeStream()

      let completionTask = Task<HTTPResponse, any Error> {
        let response = try await withCheckedThrowingContinuation { continuation in
          delegate.setHandlers(
            progressContinuation: progressContinuation,
            completionHandler: { response in
              continuation.resume(returning: response)
            },
            errorHandler: { error in
              continuation.resume(throwing: error)
            }
          )
        }

        // Move downloaded file to destination
        if let tempURL = task.currentRequest?.url {
          try FileManager.default.moveItem(at: tempURL, to: fileURL)
        }

        return response
      }

      task.resume()

      return HTTPBackgroundTask(
        taskIdentifier: task.taskIdentifier,
        sessionIdentifier: sessionIdentifier,
        urlSessionTask: task,
        progressContinuation: progressContinuation,
        completionTask: completionTask
      )
    }
  #endif

  nonisolated package var underlyingURLSession: URLSession {
    session
  }
}

package protocol HTTPClientInterceptor: Sendable {
  func intercept(
    _ request: HTTPRequest,
    next: @Sendable (HTTPRequest) async throws -> HTTPResponse
  ) async throws -> HTTPResponse
}
