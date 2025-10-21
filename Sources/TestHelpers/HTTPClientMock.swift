//
//  HTTPClientMock.swift
//
//
//  Created by Guilherme Souza on 26/04/24.
//

import ConcurrencyExtras
import Foundation
import XCTestDynamicOverlay

package final class HTTPClientMock: HTTPClientType {
  package struct MockNotFound: Error {}

  private var mocks = [@Sendable (HTTPRequest) async throws -> HTTPResponse?]()

  /// Requests received by this client in order.
  package var receivedRequests: [HTTPRequest] = []

  /// Responses returned by this client in order.
  package var returnedResponses: [Result<HTTPResponse, any Error>] = []

  package init() {}

  @discardableResult
  package func when(
    _ request: @escaping @Sendable (HTTPRequest) -> Bool,
    return response: @escaping @Sendable (HTTPRequest) async throws -> HTTPResponse
  ) -> Self {
    mocks.append { r in
      if request(r) {
        return try await response(r)
      }
      return nil
    }
    return self
  }

  @discardableResult
  package func any(
    _ response: @escaping @Sendable (HTTPRequest) async throws -> HTTPResponse
  ) -> Self {
    when({ _ in true }, return: response)
  }

  package func send(_ request: HTTPRequest) async throws -> HTTPResponse {
    receivedRequests.append(request)

    for mock in mocks {
      do {
        if let response = try await mock(request) {
          returnedResponses.append(.success(response))
          return response
        }
      } catch {
        returnedResponses.append(.failure(error))
        throw error
      }
    }

    XCTFail("Mock not found for: \(request)")
    throw MockNotFound()
  }

  package func stream(_ request: HTTPRequest) -> AsyncThrowingStream<Data, any Error> {
    fatalError("Not supported")
  }
}
