//
//  RecordingTransport.swift
//  TestHelpers
//
//  Created by Guilherme Souza on 10/09/26.
//

import ConcurrencyExtras
package import Foundation
package import HTTPTypes
package import Helpers
import IssueReporting

/// A ``ClientTransport`` that records every request it receives (with its buffered body) and
/// answers from stubs registered with ``respond(when:_:)``.
///
/// Wrap it in `HTTPClient(transport:)` for a client whose network a test controls end to end.
package struct RecordingTransport: ClientTransport {
  package typealias Handler =
    @Sendable (HTTPTypes.HTTPRequest, Data?) async throws -> (HTTPTypes.HTTPResponse, Data)

  private struct Stub {
    let matches: @Sendable (HTTPTypes.HTTPRequest) -> Bool
    let handler: Handler
  }

  private struct State {
    var requests: [(head: HTTPTypes.HTTPRequest, body: Data?)] = []
    var stubs: [Stub] = []
  }

  private let state = LockIsolated(State())

  /// Creates a transport that answers every request with `handler`, or none when `nil`.
  package init(_ handler: Handler? = nil) {
    if let handler { respond(handler) }
  }

  /// Requests received so far, in order, with their buffered bodies.
  package var requests: [(head: HTTPTypes.HTTPRequest, body: Data?)] {
    state.value.requests
  }

  /// Answers requests whose head passes `matches` (every request by default) with `handler`.
  /// Stubs are tried in registration order.
  package func respond(
    when matches: @escaping @Sendable (HTTPTypes.HTTPRequest) -> Bool = { _ in true },
    _ handler: @escaping Handler
  ) {
    state.withValue { $0.stubs.append(Stub(matches: matches, handler: handler)) }
  }

  package func send(_ request: HTTPTypes.HTTPRequest, body: HTTPBody?) async throws -> (
    HTTPTypes.HTTPResponse, HTTPBody?
  ) {
    let data: Data? =
      if let body { try await Data(collecting: body, upTo: .max) } else { nil }

    let stub = state.withValue {
      $0.requests.append((request, data))
      return $0.stubs.first { $0.matches(request) }
    }
    guard let stub else {
      reportIssue("No stub matches request: \(request)")
      throw MissingStubError()
    }

    let (head, responseData) = try await stub.handler(request, data)
    return (head, responseData.isEmpty ? nil : HTTPBody(responseData))
  }

  package struct MissingStubError: Error {}
}
