//
//  HTTPTransportStub.swift
//  HTTPRuntimeTestHelpers
//
//  Created by Guilherme Souza on 11/07/26.
//
import Foundation
package import HTTPRuntime
import Testing

/// Thrown into `HTTPError.transport` on a stub mismatch — the actual test
/// failure is the `Issue.record` call alongside it; this just gives the code
/// under test a real error to handle if it inspects the failure.
package struct HTTPStubMismatch: Error, CustomStringConvertible {
  package let description: String
}

/// The `HTTPTransport` backing `.http(stubs:)` — an ordered, consume-once
/// stub queue. Bound to the current task tree via `HTTPStubTrait` (below).
package actor HTTPTransportStub: HTTPTransport {
  @TaskLocal fileprivate static var _current: HTTPTransportStub?

  /// The stub transport bound by the enclosing `.http(stubs:)` trait scope.
  /// Outside such a scope, accessing this records an issue and returns an
  /// empty-queue instance — any request against it fails through the normal
  /// "no stubs remaining" path below rather than crashing.
  package static var current: HTTPTransportStub {
    guard let value = _current else {
      Issue.record("HTTPTransportStub.current accessed outside a .http trait scope")
      return HTTPTransportStub(stubs: [])
    }
    return value
  }

  private var pending: [HTTPStub]
  private var consumedRequests: [HTTPRequest] = []

  package init(stubs: [HTTPStub]) {
    pending = stubs
  }

  private func nextMatchingStub(for request: HTTPRequest) throws(HTTPError) -> HTTPStub {
    consumedRequests.append(request)
    guard !pending.isEmpty else {
      let message =
        "Unexpected request \(request.method.rawValue) \(request.url.absoluteString) — no stubs remaining"
      Issue.record("\(message)")
      throw HTTPError.transport(HTTPStubMismatch(description: message))
    }
    let stub = pending.removeFirst()
    guard stub.method == request.method, stub.url == request.url.absoluteString else {
      let message = """
        Request mismatch.
        Expected: \(stub.method.rawValue) \(stub.url)
        Actual:   \(request.method.rawValue) \(request.url.absoluteString)
        """
      Issue.record("\(message)")
      throw HTTPError.transport(HTTPStubMismatch(description: message))
    }
    return stub
  }

  package func send(_ request: HTTPRequest, uploadProgress: ProgressHandler?)
    async throws(HTTPError)
    -> HTTPResponse
  {
    let stub = try nextMatchingStub(for: request)
    let bodyData: Data
    switch stub.body() {
    case .empty:
      bodyData = Data()
    case .string(let value):
      bodyData = Data(value.utf8)
    case .data(let value):
      bodyData = value
    case .stream(let stream):
      var collected = Data()
      for await chunk in stream { collected.append(chunk) }
      bodyData = collected
    }
    return HTTPResponse(
      head: HTTPResponseHead(status: stub.status, headers: stub.headers), body: bodyData)
  }

  package func stream(_ request: HTTPRequest) async throws(HTTPError) -> HTTPResponseStream {
    let stub = try nextMatchingStub(for: request)
    let responseBody: AsyncThrowingStream<Data, any Error>
    switch stub.body() {
    case .empty:
      responseBody = AsyncThrowingStream { $0.finish() }
    case .string(let value):
      responseBody = AsyncThrowingStream { continuation in
        continuation.yield(Data(value.utf8))
        continuation.finish()
      }
    case .data(let value):
      responseBody = AsyncThrowingStream { continuation in
        continuation.yield(value)
        continuation.finish()
      }
    case .stream(let stream):
      responseBody = AsyncThrowingStream { continuation in
        let task = Task {
          for await chunk in stream { continuation.yield(chunk) }
          continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
      }
    }
    return HTTPResponseStream(
      head: HTTPResponseHead(status: stub.status, headers: stub.headers), body: responseBody)
  }

  /// Records an issue for every stub that was never consumed. Called by
  /// `HTTPStubTrait` at scope exit.
  package func assertAllConsumed() {
    for stub in pending {
      Issue.record("Stub for \(stub.method.rawValue) \(stub.url) was never consumed")
    }
  }

  /// Count of requests recorded so far — `assertHTTPRequests` snapshots this
  /// before running its operation, then diffs against it after.
  package var requestCount: Int { consumedRequests.count }

  /// Requests recorded from `index` onward.
  package func requests(since index: Int) -> [HTTPRequest] { Array(consumedRequests[index...]) }

  /// Stubs not yet consumed — read by `HTTPStubTrait` (below) to merge a
  /// suite-level queue with a nested test-level one.
  fileprivate var remainingStubs: [HTTPStub] { pending }
}
