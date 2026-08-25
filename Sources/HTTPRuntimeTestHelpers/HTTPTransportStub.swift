//
//  HTTPTransportStub.swift
//  HTTPRuntimeTestHelpers
//
//  Created by Guilherme Souza on 11/07/26.
//
import Foundation
package import HTTPRuntime
package import HTTPTypes
import HTTPTypesFoundation
package import Testing

/// Thrown into `HTTPRuntimeError.transport` on a stub mismatch — the actual test
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
  private var consumedRequests: [(request: HTTPRequest, body: HTTPBody?)] = []

  package init(stubs: [HTTPStub]) {
    pending = stubs
  }

  private func nextMatchingStub(for request: HTTPRequest, body: HTTPBody?) throws(HTTPRuntimeError)
    -> HTTPStub
  {
    consumedRequests.append((request, body))
    // `HTTPTypes.HTTPRequest.url` is optional — it is nil when the scheme,
    // authority or path pseudo header fields are missing. Report that as a
    // mismatch rather than letting it compare equal to nothing.
    let actualURL = request.url?.absoluteString ?? "<no URL>"
    guard !pending.isEmpty else {
      let message =
        "Unexpected request \(request.method.rawValue) \(actualURL) — no stubs remaining"
      Issue.record("\(message)")
      throw HTTPRuntimeError.transport(HTTPStubMismatch(description: message))
    }
    let stub = pending.removeFirst()
    guard stub.method == request.method, stub.url == actualURL else {
      let message = """
        Request mismatch.
        Expected: \(stub.method.rawValue) \(stub.url)
        Actual:   \(request.method.rawValue) \(actualURL)
        """
      Issue.record("\(message)")
      throw HTTPRuntimeError.transport(HTTPStubMismatch(description: message))
    }
    return stub
  }

  package func send(_ request: HTTPRequest, body: HTTPBody?, uploadProgress: ProgressHandler?)
    async throws(HTTPRuntimeError) -> HTTPBufferedResponse
  {
    let stub = try nextMatchingStub(for: request, body: body)
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
    return HTTPBufferedResponse(
      head: HTTPResponse(status: stub.status, headerFields: stub.headers), body: bodyData)
  }

  package func stream(_ request: HTTPRequest, body: HTTPBody?) async throws(HTTPRuntimeError)
    -> HTTPStreamedResponse
  {
    let stub = try nextMatchingStub(for: request, body: body)
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
    return HTTPStreamedResponse(
      head: HTTPResponse(status: stub.status, headerFields: stub.headers), body: responseBody)
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

  /// Requests recorded from `index` onward, each paired with the body it was
  /// sent with.
  package func requests(since index: Int) -> [(request: HTTPRequest, body: HTTPBody?)] {
    Array(consumedRequests[index...])
  }

  /// Hands off stubs not yet consumed to a nested `HTTPStubTrait` scope
  /// (below), clearing this instance's own queue in the process — the nested
  /// scope's transport takes over responsibility for them, so this instance
  /// won't also flag them as leftover when its own scope exits.
  fileprivate func takeRemainingStubs() -> [HTTPStub] {
    defer { pending = [] }
    return pending
  }
}

/// Declares canned responses for `HTTPTransport`-issued requests made during
/// a test. Usable at `@Test` or `@Suite` level; a `@Test`-level trait appends
/// its stubs to whatever an enclosing `@Suite`-level trait already queued,
/// preserving order.
package struct HTTPStubTrait: TestTrait, SuiteTrait, TestScoping {
  package let isRecursive = true

  fileprivate let stubs: [HTTPStub]

  package func provideScope(
    for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
  ) async throws {
    let outerStubs = await HTTPTransportStub._current?.takeRemainingStubs() ?? []
    let transport = HTTPTransportStub(stubs: outerStubs + stubs)
    try await HTTPTransportStub.$_current.withValue(transport) {
      try await function()
      await transport.assertAllConsumed()
    }
  }
}

extension Trait where Self == HTTPStubTrait {
  /// `@Test(.http(stubs: [.get("https://example.com/x") { .string("...") }]))`
  ///
  /// Declared here (rather than relying on the free `http(stubs:)` function
  /// below) because leading-dot trait syntax only resolves through a static
  /// member on `Trait` — a free function isn't found by that lookup.
  package static func http(stubs: [HTTPStub]) -> Self {
    HTTPStubTrait(stubs: stubs)
  }
}

/// Constructs an `HTTPStubTrait` directly, e.g. to drive `provideScope(...)`
/// by hand in a test body rather than via `@Test(.http(stubs:))`.
package func http(stubs: [HTTPStub]) -> HTTPStubTrait {
  HTTPStubTrait(stubs: stubs)
}
