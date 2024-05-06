//
//  HTTPClientMock.swift
//
//
//  Created by Guilherme Souza on 26/04/24.
//

import _Helpers
import ConcurrencyExtras
import Foundation
import XCTestDynamicOverlay

package final class HTTPClientMock: HTTPClientType {
  package struct MockNotFound: Error {}

  private let mocks: LockIsolated < [@Sendable (HTTPRequest) async throws -> HTTPResponse?]> = .init([])
  private let _receivedRequests = LockIsolated<[HTTPRequest]>([])
  private let _returnedResponses = LockIsolated<[Result<HTTPResponse, any Error>]>([])

  /// Requests received by this client in order.
  package var receivedRequests: [HTTPRequest] {
    _receivedRequests.value
  }

  /// Responses returned by this client in order.
  package var returnedResponses: [Result<HTTPResponse, any Error>] {
    _returnedResponses.value
  }

  package init() {}

  @discardableResult
  package func when(
    _ request: @escaping @Sendable (HTTPRequest) -> Bool,
    return response: @escaping @Sendable (HTTPRequest) async throws -> HTTPResponse
  ) -> Self {
    mocks.withValue {
      $0.append { r in
        if request(r) {
          return try await response(r)
        }

        return nil
      }
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
    _receivedRequests.withValue { $0.append(request) }

    for mock in mocks.value {
      do {
        if let response = try await mock(request) {
          _returnedResponses.withValue {
            $0.append(.success(response))
          }
          return response
        }
      } catch {
        _returnedResponses.withValue {
          $0.append(.failure(error))
        }
        throw error
      }
    }

    XCTFail("Mock not found for: \(request)")
    throw MockNotFound()
  }
}
