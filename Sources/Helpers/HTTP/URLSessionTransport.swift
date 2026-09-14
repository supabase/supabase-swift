//
//  URLSessionTransport.swift
//  Helpers
//
//  Created by Guilherme Souza on 09/09/26.
//

import ConcurrencyExtras
public import Foundation
public import HTTPTypes
import HTTPTypesFoundation

#if canImport(FoundationNetworking)
  public import FoundationNetworking
#endif

/// The default ``ClientTransport``, backed by `URLSession`.
///
/// - Bodies created with ``HTTPBody/init(_:)`` upload from memory; bodies created with
///   ``HTTPBody/init(fileURL:)`` stream from disk through `upload(for:fromFile:)`.
/// - Response bodies stream on Apple platforms: the head is returned as soon as it arrives and
///   each chunk is one `didReceive(data:)` delivery from `URLSession`, so chunk boundaries follow
///   the network, not the payload. swift-corelibs-foundation has no per-task delegates, so on
///   Linux the response is buffered and delivered as one chunk.
/// - The SDK sets `URLRequest.timeoutInterval` on every request it sends (60 seconds by default,
///   `FunctionInvokeOptions.timeoutInterval` for Functions), so it wins over the session's
///   `timeoutIntervalForRequest`.
/// - A buffered response body is `.multiple`, while a streamed one is `.single`, so
///   replay-sensitive middleware behaves differently per platform.
/// - An empty response body comes back as `nil` on Linux but as a non-nil body that yields no
///   chunks on Apple platforms, so middleware must not branch on `body == nil` to detect
///   emptiness — collect the body and check its byte count instead.
///
/// ```swift
/// let configuration = URLSessionConfiguration.default
/// configuration.httpAdditionalHeaders = ["X-App": "demo"]
/// let transport = URLSessionTransport(configuration: configuration)
/// ```
public struct URLSessionTransport: ClientTransport {
  private let session: URLSession

  /// Creates a transport over an existing session. Defaults to `URLSession.shared`.
  public init(session: URLSession = .shared) {
    self.session = session
  }

  /// Creates a transport with its own session built from `configuration`.
  public init(configuration: URLSessionConfiguration) {
    self.init(session: URLSession(configuration: configuration))
  }

  /// Sends `request` through the session; see the type documentation for how each body kind
  /// is uploaded.
  public func send(_ request: HTTPTypes.HTTPRequest, body: HTTPBody?) async throws -> (
    HTTPTypes.HTTPResponse, HTTPBody?
  ) {
    var urlRequest = try Self.makeURLRequest(request)
    if let timeout = RequestTimeout.current {
      urlRequest.timeoutInterval = timeout
    }
    // URLSession treats Content-Length as reserved and recomputes it from the body; setting it
    // here keeps custom URLProtocol observers (tests) and non-URLSession callers of this header
    // path consistent.
    if let body, case .known(let count) = body.length,
      urlRequest.value(forHTTPHeaderField: "Content-Length") == nil
    {
      urlRequest.setValue(String(count), forHTTPHeaderField: "Content-Length")
    }

    if let body {
      switch body.storage {
      case .file(let fileURL):
        let (data, response) = try await session.upload(for: urlRequest, fromFile: fileURL)
        return (try Self.makeHead(response), Self.makeBody(data))
      case .data(let data):
        urlRequest.httpBody = data
      case .stream:
        // ponytail: streamed request bodies buffer in memory; uploadTask(withStreamedRequest:)
        // with an InputStream bridge is the upgrade when SDK-850 needs progress on them.
        urlRequest.httpBody = try await Data(collecting: body, upTo: .max)
      }
    }
    return try await streamResponse(for: urlRequest)
  }

  #if canImport(FoundationNetworking)
    private func streamResponse(for urlRequest: URLRequest) async throws -> (
      HTTPTypes.HTTPResponse, HTTPBody?
    ) {
      let (data, response) = try await session.data(for: urlRequest)
      return (try Self.makeHead(response), Self.makeBody(data))
    }
  #else
    private func streamResponse(for urlRequest: URLRequest) async throws -> (
      HTTPTypes.HTTPResponse, HTTPBody?
    ) {
      // ponytail: the chunk stream is unbounded, so a consumer slower than the network holds
      // the backlog; suspend/resume the task on a watermark if that shows up (SDK-1833).
      let (chunks, continuation) = AsyncThrowingStream<ArraySlice<UInt8>, any Error>.makeStream()
      let task = session.dataTask(with: urlRequest)
      let delegate = StreamingTaskDelegate(body: continuation)
      task.delegate = delegate
      continuation.onTermination = { _ in task.cancel() }

      let response = try await withTaskCancellationHandler {
        try await delegate.head(starting: task)
      } onCancel: {
        task.cancel()
      }
      let head = try Self.makeHead(response)
      let length: HTTPBody.Length =
        response.expectedContentLength >= 0 ? .known(response.expectedContentLength) : .unknown
      let body = HTTPBody(storage: .stream, length: length, iterationBehavior: .single) { chunks }
      return (head, body)
    }
  #endif

  private static func makeURLRequest(_ request: HTTPTypes.HTTPRequest) throws -> URLRequest {
    guard let urlRequest = URLRequest(httpRequest: request) else {
      throw URLError(.badURL)
    }
    return urlRequest
  }

  private static func makeHead(_ response: URLResponse) throws -> HTTPTypes.HTTPResponse {
    guard let head = (response as? HTTPURLResponse)?.httpResponse else {
      throw URLError(.badServerResponse)
    }
    return head
  }

  private static func makeBody(_ data: Data) -> HTTPBody? {
    data.isEmpty ? nil : HTTPBody(data)
  }
}

#if !canImport(FoundationNetworking)
  /// Per-task delegate that hands the response head to `head(starting:)` and forwards every
  /// `didReceive(data:)` delivery to the body stream as one chunk.
  private final class StreamingTaskDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private enum State {
      case idle
      case waitingForHead(CheckedContinuation<URLResponse, any Error>)
      case headDelivered
      case finished
    }

    private let body: AsyncThrowingStream<ArraySlice<UInt8>, any Error>.Continuation
    private let state = LockIsolated(State.idle)

    init(body: AsyncThrowingStream<ArraySlice<UInt8>, any Error>.Continuation) {
      self.body = body
    }

    /// Starts `task` and returns its response as soon as the headers arrive. Throws if the task
    /// fails before that.
    func head(starting task: URLSessionTask) async throws -> URLResponse {
      try await withCheckedThrowingContinuation { continuation in
        state.setValue(.waitingForHead(continuation))
        task.resume()
      }
    }

    func urlSession(
      _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
      completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
      takePendingHead()?.resume(returning: response)
      completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
      body.yield(ArraySlice(data))
    }

    func urlSession(
      _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
    ) {
      let pending = takePendingHead(finished: true)
      if let error {
        pending?.resume(throwing: error)
        body.finish(throwing: error)
      } else {
        // Completing without ever delivering a response is not a valid HTTP exchange.
        pending?.resume(throwing: URLError(.badServerResponse))
        body.finish()
      }
    }

    /// Returns the head continuation if it is still waiting, advancing the state exactly once.
    private func takePendingHead(finished: Bool = false) -> CheckedContinuation<
      URLResponse, any Error
    >? {
      state.withValue { state in
        defer { state = finished ? .finished : .headDelivered }
        if case .waitingForHead(let continuation) = state { return continuation }
        return nil
      }
    }
  }
#endif
