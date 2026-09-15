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
///   ``HTTPBody/init(fileURL:)`` stream from disk through an upload task. Any other body streams
///   chunk by chunk on Apple platforms through `uploadTask(withStreamedRequest:)`, pulling the
///   next chunk only when `URLSession` has room for it; a ``HTTPBody/Length/known(_:)`` length
///   is sent as `Content-Length` and the body must yield exactly that many bytes or the request
///   fails with ``HTTPBodyLengthMismatchError``, an ``HTTPBody/Length/unknown`` one uses chunked
///   transfer. Because the body is pulled while the request is in flight, a gap between chunks
///   longer than the request timeout fails the request with `URLError.timedOut`. On Linux,
///   swift-corelibs-foundation has no per-task delegates to feed a stream from, so such bodies
///   are first spooled to a temporary file (checked against a known length the same way) and
///   uploaded from there, and a progress wrapper on an in-memory or file body reports once, when
///   the upload completes.
/// - On Apple platforms a ``HTTPBody/IterationBehavior/single`` body cannot be sent twice. A 307
///   or 308 redirect, which would resend it, is not followed: the redirect response is returned
///   to the caller as-is. If `URLSession` asks for the body again for any other reason (an
///   authentication retry), the request fails with ``HTTPBodyAlreadyConsumedError``. On Linux the
///   spooled copy can be resent, so redirects are followed for every body kind.
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
    // URLSession recomputes Content-Length from an in-memory or file body, but it cannot see the
    // length of a streamed one and falls back to chunked transfer without this header. Setting
    // it here also keeps custom URLProtocol observers (tests) consistent across body kinds.
    if let body, case .known(let count) = body.length,
      urlRequest.value(forHTTPHeaderField: "Content-Length") == nil
    {
      urlRequest.setValue(String(count), forHTTPHeaderField: "Content-Length")
    }
    if case .data(let data)? = body?.storage {
      urlRequest.httpBody = data
    }

    #if canImport(FoundationNetworking)
      var fileURL: URL?
      var spool: URL?
      defer { if let spool { try? FileManager.default.removeItem(at: spool) } }
      if case .file(let url)? = body?.storage {
        fileURL = url
      } else if let body, case .stream = body.storage {
        // swift-corelibs-foundation has no per-task delegates to feed a body stream from, so the
        // body is spooled to disk first and uploaded from there; memory stays flat either way.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        spool = url
        try await body.write(to: url)
        // Content-Length already carries the declared count, so the spooled size must match it.
        if case .known(let declared) = body.length {
          let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
          let actual = (attributes[.size] as? NSNumber)?.int64Value ?? 0
          guard actual == declared else {
            throw HTTPBodyLengthMismatchError(declared: declared, actual: actual)
          }
        }
        fileURL = url
      }
      let (data, response) =
        if let fileURL {
          try await session.upload(for: urlRequest, fromFile: fileURL)
        } else {
          try await session.data(for: urlRequest)
        }
      // Nothing reports sent bytes on this platform, so a progress wrapper on an in-memory or
      // file body hears once, when the upload has completed.
      if let body, case .known(let count) = body.length { body.onUploadProgress?(count) }
      return (try Self.makeHead(response), Self.makeBody(data))
    #else
      let task: URLSessionTask
      switch body?.storage {
      case .file(let fileURL)?:
        task = session.uploadTask(with: urlRequest, fromFile: fileURL)
      case .stream?:
        task = session.uploadTask(withStreamedRequest: urlRequest)
      case .data?, nil:
        task = session.dataTask(with: urlRequest)
      }
      return try await streamResponse(from: task, requestBody: body)
    #endif
  }

  #if !canImport(FoundationNetworking)
    private func streamResponse(from task: URLSessionTask, requestBody: HTTPBody?) async throws
      -> (HTTPTypes.HTTPResponse, HTTPBody?)
    {
      // ponytail: the chunk stream is unbounded, so a consumer slower than the network holds
      // the backlog; suspend/resume the task on a watermark if that shows up (SDK-1833).
      let (chunks, continuation) = AsyncThrowingStream<ArraySlice<UInt8>, any Error>.makeStream()
      let delegate = StreamingTaskDelegate(body: continuation, requestBody: requestBody)
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
  /// Per-task delegate that hands the response head to `head(starting:)`, forwards every
  /// `didReceive(data:)` delivery to the body stream as one chunk, and feeds a streamed request
  /// body to `URLSession` through ``HTTPBodyOutputStreamBridge`` whenever it asks for one.
  final class StreamingTaskDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private enum State {
      case idle
      case waitingForHead(CheckedContinuation<URLResponse, any Error>)
      case headDelivered
      case finished
    }

    private let body: AsyncThrowingStream<ArraySlice<UInt8>, any Error>.Continuation
    private let requestBody: HTTPBody?
    private let state = LockIsolated(State.idle)
    /// Feeds the current request body stream; replaced on every `needNewBodyStream`.
    private let bridge = LockIsolated<HTTPBodyOutputStreamBridge?>(nil)
    /// Why the request body could not be sent, reported in place of URLSession's `.cancelled`.
    private let requestBodyError = LockIsolated<(any Error)?>(nil)

    init(
      body: AsyncThrowingStream<ArraySlice<UInt8>, any Error>.Continuation,
      requestBody: HTTPBody? = nil
    ) {
      self.body = body
      self.requestBody = requestBody
    }

    func urlSession(
      _ session: URLSession, task: URLSessionTask,
      needNewBodyStream completionHandler: @escaping @Sendable (InputStream?) -> Void
    ) {
      var input: InputStream?
      var output: OutputStream?
      if requestBody != nil {
        Stream.getBoundStreams(
          withBufferSize: 64 * 1024, inputStream: &input, outputStream: &output)
      }
      guard let requestBody, let input, let output else {
        completionHandler(nil)
        return
      }
      // Each call gets a fresh iterator: a `.multiple` body replays, a `.single` body throws
      // `HTTPBodyAlreadyConsumedError` on its first pull, which fails the task through here.
      // (307/308 redirects never get this far for a `.single` body; see below.)
      let next = HTTPBodyOutputStreamBridge(body: requestBody, output: output) {
        [requestBodyError] error in
        requestBodyError.withValue { $0 = $0 ?? error }
        task.cancel()
      }
      bridge.withValue { current in
        current?.cancel()
        current = next
      }
      completionHandler(input)
    }

    func urlSession(
      _ session: URLSession, task: URLSessionTask,
      willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
      completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
      // 307 and 308 keep the method and resend the body (the other 3xx codes turn into a bodiless
      // GET). A one-shot body cannot be sent again, so the redirect response is returned as-is
      // rather than failing the request halfway through — the same rule Go's net/http applies.
      let resendsBody = response.statusCode == 307 || response.statusCode == 308
      completionHandler(resendsBody && requestBody?.iterationBehavior == .single ? nil : request)
    }

    func urlSession(
      _ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
      totalBytesSent: Int64, totalBytesExpectedToSend: Int64
    ) {
      // Only `.file` and `.data` bodies set this hook; a streamed body reports as it is pulled.
      requestBody?.onUploadProgress?(totalBytesSent)
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
      bridge.withValue { current in
        current?.cancel()
        current = nil
      }
      let pending = takePendingHead(finished: true)
      if let error {
        let error = requestBodyError.value ?? error
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
