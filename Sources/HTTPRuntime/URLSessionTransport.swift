//
//  URLSessionTransport.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 08/07/26.
//
package import Foundation
package import HTTPTypes
import HTTPTypesFoundation

#if canImport(FoundationNetworking)
  package import FoundationNetworking
#endif

/// The default, zero-dependency `HTTPTransport` backed by `URLSession`.
///
/// Design notes (and a real URLSession constraint worth recording):
/// - Buffered and streaming requests use the modern async `URLSession` APIs
///   (`upload(for:fromFile:)`, `bytes(for:)`), which keep the code fully
///   async/await + `AsyncSequence` and Sendable-clean.
/// - Uploads stream from a file on disk (`.file`, including caller-assembled
///   multipart bodies), so large bodies never fully buffer in memory. Progress
///   is reported via a per-task delegate.
/// - Background sessions are exposed via `init(configuration:)`, BUT the async
///   convenience APIs are not supported on a background `URLSessionConfiguration`
///   — background transfers must use delegate-based `downloadTask`/`uploadTask`
///   that complete out-of-process. That path is documented as a known limitation
///   rather than faked here.
/// - `URLRequest(httpRequest:)` carries no timeout, and `HTTPTypes.HTTPRequest`
///   has no field for one, so there is no per-request timeout here — only the
///   session-wide `URLSessionConfiguration.timeoutIntervalForRequest`.
///   Supporting a per-request timeout means building the `URLRequest` by hand
///   and giving up the `HTTPTypesFoundation` conveniences above.
package struct URLSessionTransport: HTTPTransport {
  private let session: URLSession

  package init(configuration: URLSessionConfiguration = .default) {
    self.session = URLSession(configuration: configuration)
  }

  package init(session: URLSession) {
    self.session = session
  }

  package func send(_ request: HTTPRequest, body: HTTPBody?, uploadProgress: ProgressHandler?)
    async throws(HTTPRuntimeError) -> HTTPBufferedResponse
  {
    let delegate = uploadProgress.map { ProgressDelegate(onProgress: $0) }

    let data: Data
    let response: HTTPResponse
    do {
      switch body {
      case nil:
        (data, response) = try await session.data(for: request, delegate: delegate)
      case .data(let payload):
        (data, response) = try await session.upload(
          for: request, from: payload, delegate: delegate)
      case .file(let fileURL):
        (data, response) = try await session.upload(
          for: request, fromFile: fileURL, delegate: delegate)
      }
    } catch {
      throw HTTPRuntimeError.transport(error)
    }
    return HTTPBufferedResponse(head: response, body: data)
  }

  #if canImport(FoundationNetworking)
    // swift-corelibs-foundation has no async byte-streaming API
    // (`bytes(for:)`/`AsyncBytes`), so on Linux the response is buffered in
    // full and delivered as a single chunk instead of streamed incrementally.
    package func stream(_ request: HTTPRequest, body: HTTPBody?) async throws(HTTPRuntimeError)
      -> HTTPStreamedResponse
    {
      try Self.rejectFileBody(body)
      let data: Data
      let response: HTTPResponse
      if case .data(let payload) = body {
        // The `HTTPRequest` convenience carries no body, so a request that has
        // one has to go through a hand-built `URLRequest`.
        var urlRequest = try Self.makeURLRequest(for: request)
        urlRequest.httpBody = payload
        let urlResponse: URLResponse
        do {
          (data, urlResponse) = try await session.data(for: urlRequest)
        } catch {
          throw HTTPRuntimeError.transport(error)
        }
        response = try Self.makeHTTPResponse(from: urlResponse)
      } else {
        do {
          (data, response) = try await session.data(for: request)
        } catch {
          throw HTTPRuntimeError.transport(error)
        }
      }
      let body = AsyncThrowingStream<Data, any Error> { continuation in
        continuation.yield(data)
        continuation.finish()
      }
      return HTTPStreamedResponse(head: response, body: body)
    }
  #else
    package func stream(_ request: HTTPRequest, body: HTTPBody?) async throws(HTTPRuntimeError)
      -> HTTPStreamedResponse
    {
      try Self.rejectFileBody(body)
      let bytes: URLSession.AsyncBytes
      let response: HTTPResponse
      if case .data(let payload) = body {
        // The `HTTPRequest` convenience carries no body, so a request that has
        // one has to go through a hand-built `URLRequest`.
        var urlRequest = try Self.makeURLRequest(for: request)
        urlRequest.httpBody = payload
        let urlResponse: URLResponse
        do {
          (bytes, urlResponse) = try await session.bytes(for: urlRequest)
        } catch {
          throw HTTPRuntimeError.transport(error)
        }
        response = try Self.makeHTTPResponse(from: urlResponse)
      } else {
        do {
          (bytes, response) = try await session.bytes(for: request)
        } catch {
          throw HTTPRuntimeError.transport(error)
        }
      }

      let body = AsyncThrowingStream<Data, any Error> { continuation in
        let task = Task {
          do {
            var buffer = [UInt8]()
            buffer.reserveCapacity(16 * 1024)
            for try await byte in bytes {
              buffer.append(byte)
              // Flush on newline (prompt SSE frame delivery) or when a
              // chunk fills up (bounded memory for large downloads).
              if byte == 0x0A || buffer.count >= 16 * 1024 {
                continuation.yield(Data(buffer))
                buffer.removeAll(keepingCapacity: true)
              }
            }
            if !buffer.isEmpty { continuation.yield(Data(buffer)) }
            continuation.finish()
          } catch {
            continuation.finish(throwing: HTTPRuntimeError.transport(error))
          }
        }
        continuation.onTermination = { _ in task.cancel() }
      }

      return HTTPStreamedResponse(head: response, body: body)
    }
  #endif

  // MARK: - Helpers

  /// `stream(_:body:)` sends a `.data` body by attaching it to a hand-built
  /// `URLRequest`, which buffers the whole payload in memory. A `.file` body
  /// exists precisely so a large payload never does that, so streaming one
  /// through the same path would defeat its purpose. Reject it up front and
  /// point at `send(_:body:uploadProgress:)`, which streams the file from disk.
  private static func rejectFileBody(_ body: HTTPBody?) throws(HTTPRuntimeError) {
    if case .file = body {
      throw HTTPRuntimeError.unsupportedRequestBody(
        "stream(_:) does not support file-backed request bodies; use send(_:uploadProgress:) instead."
      )
    }
  }

  /// `URLRequest(httpRequest:)` is failable, and returns nil exactly when the
  /// request's pseudo-header fields do not form a URL. Force-unwrapping those
  /// same fields to build an error would crash in that case, so map the nil to
  /// `.transport` instead.
  private static func makeURLRequest(for request: HTTPRequest) throws(HTTPRuntimeError)
    -> URLRequest
  {
    guard let urlRequest = URLRequest(httpRequest: request) else {
      throw HTTPRuntimeError.transport(URLError(.badURL))
    }
    return urlRequest
  }

  /// The `URLRequest`-taking URLSession calls hand back a `URLResponse` rather
  /// than an `HTTPResponse`, so convert, without force-unwrapping a response
  /// that turns out not to be an HTTP one.
  private static func makeHTTPResponse(from response: URLResponse) throws(HTTPRuntimeError)
    -> HTTPResponse
  {
    guard let httpResponse = (response as? HTTPURLResponse)?.httpResponse else {
      throw HTTPRuntimeError.transport(URLError(.badServerResponse))
    }
    return httpResponse
  }
}

/// Per-task delegate that forwards upload progress.
private final class ProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
  private let onProgress: ProgressHandler

  init(onProgress: @escaping ProgressHandler) {
    self.onProgress = onProgress
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64,
    totalBytesExpectedToSend: Int64
  ) {
    let total = totalBytesExpectedToSend > 0 ? totalBytesExpectedToSend : nil
    onProgress(TransferProgress(completed: totalBytesSent, total: total))
  }
}
