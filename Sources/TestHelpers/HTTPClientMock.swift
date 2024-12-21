//
//  HTTPClientMock.swift
//
//
//  Created by Guilherme Souza on 26/04/24.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import XCTestDynamicOverlay

package actor HTTPClientMock: HTTPClientType {

  package struct MockNotFound: Error {}

  private var mocks = [@Sendable (HTTPRequest, Data?) async throws -> (Data, HTTPResponse)?]()

  /// Requests received by this client in order.
  package var receivedRequests: [(HTTPRequest, Data?)] = []

  /// Responses returned by this client in order.
  package var returnedResponses: [Result<HTTPResponse, any Error>] = []

  package init() {}

  @discardableResult
  package func when(
    _ request: @escaping @Sendable (HTTPRequest, Data?) -> Bool,
    return response: @escaping @Sendable (HTTPRequest, Data?) async throws -> (Data, HTTPResponse)
  ) -> Self {
    mocks.append { r, b in
      if request(r, b) {
        return try await response(r, b)
      }
      return nil
    }
    return self
  }

  @discardableResult
  package func any(
    _ response: @escaping @Sendable (HTTPRequest, Data?) async throws -> (Data, HTTPResponse)
  ) -> Self {
    when({ _, _ in true }, return: response)
  }

  package func send(
    _ request: HTTPRequest,
    _ bodyData: Data?
  ) async throws -> (Data, HTTPResponse) {
    receivedRequests.append((request, bodyData))

    for mock in mocks {
      do {
        if let (data, response) = try await mock(request, bodyData) {
          returnedResponses.append(.success(response))
          return (data, response)
        }
      } catch {
        returnedResponses.append(.failure(error))
        throw error
      }
    }

    XCTFail("Mock not found for: \(request)")
    throw MockNotFound()
  }
}
