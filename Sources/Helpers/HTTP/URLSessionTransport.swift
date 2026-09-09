//
//  URLSessionTransport.swift
//  Helpers
//
//  Created by Guilherme Souza on 09/09/26.
//

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
/// - Response bodies stream on Apple platforms. swift-corelibs-foundation has no
///   `URLSession.bytes(for:)`, so on Linux the response is buffered and delivered as one chunk.
/// - Timeouts come from the session's `URLSessionConfiguration`, plus the SDK's internal
///   per-request override where a sub-client sets one (Functions).
///
/// ```swift
/// let configuration = URLSessionConfiguration.default
/// configuration.timeoutIntervalForRequest = 30
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

  public func send(_ request: HTTPTypes.HTTPRequest, body: HTTPBody?) async throws -> (
    HTTPTypes.HTTPResponse, HTTPBody?
  ) {
    var urlRequest = try Self.makeURLRequest(request)
    if let timeout = RequestTimeout.current {
      urlRequest.timeoutInterval = timeout
    }
    if let body, case .known(let count) = body.length,
      urlRequest.value(forHTTPHeaderField: "Content-Length") == nil
    {
      urlRequest.setValue(String(count), forHTTPHeaderField: "Content-Length")
    }

    if let body {
      switch body.storage {
      case .file(let fileURL):
        let (data, response) = try await session.upload(for: urlRequest, fromFile: fileURL)
        return (try Self.makeHead(response), Self.makeBody(data, from: response))
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
      return (try Self.makeHead(response), Self.makeBody(data, from: response))
    }
  #else
    private func streamResponse(for urlRequest: URLRequest) async throws -> (
      HTTPTypes.HTTPResponse, HTTPBody?
    ) {
      let (bytes, response) = try await session.bytes(for: urlRequest)
      let head = try Self.makeHead(response)
      let length: HTTPBody.Length =
        response.expectedContentLength >= 0 ? .known(response.expectedContentLength) : .unknown
      let body = HTTPBody(storage: .stream, length: length, iterationBehavior: .single) {
        AsyncThrowingStream { continuation in
          let task = Task {
            do {
              var buffer = [UInt8]()
              buffer.reserveCapacity(16 * 1024)
              for try await byte in bytes {
                buffer.append(byte)
                // Flush on newline (prompt SSE frame delivery) or when a chunk fills up
                // (bounded memory for large downloads).
                if byte == 0x0A || buffer.count >= 16 * 1024 {
                  continuation.yield(ArraySlice(buffer))
                  buffer.removeAll(keepingCapacity: true)
                }
              }
              if !buffer.isEmpty { continuation.yield(ArraySlice(buffer)) }
              continuation.finish()
            } catch {
              continuation.finish(throwing: error)
            }
          }
          continuation.onTermination = { _ in task.cancel() }
        }
      }
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

  private static func makeBody(_ data: Data, from response: URLResponse) -> HTTPBody? {
    data.isEmpty && response.expectedContentLength == 0 ? nil : HTTPBody(data)
  }
}
