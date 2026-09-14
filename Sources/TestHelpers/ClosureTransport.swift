//
//  ClosureTransport.swift
//  TestHelpers
//
//  Created by Guilherme Souza on 09/09/26.
//

package import HTTPTypes
package import Helpers

/// A ``ClientTransport`` backed by a closure, for tests that need to inspect the outgoing
/// request or hand back a response built by hand instead of proxying through `URLSession`.
package struct ClosureTransport: ClientTransport {
  let handler:
    @Sendable (HTTPTypes.HTTPRequest, HTTPBody?) async throws -> (
      HTTPTypes.HTTPResponse, HTTPBody?
    )

  package init(
    handler:
      @escaping @Sendable (HTTPTypes.HTTPRequest, HTTPBody?) async throws -> (
        HTTPTypes.HTTPResponse, HTTPBody?
      )
  ) {
    self.handler = handler
  }

  package func send(_ request: HTTPTypes.HTTPRequest, body: HTTPBody?) async throws -> (
    HTTPTypes.HTTPResponse, HTTPBody?
  ) {
    try await handler(request, body)
  }
}
