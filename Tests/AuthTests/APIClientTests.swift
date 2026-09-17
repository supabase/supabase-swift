//
//  APIClientTests.swift
//  AuthTests
//
//  Created by Guilherme Souza on 15/09/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@testable import Auth

@Suite
struct APIClientTests {
  @Test
  func rateLimitedRequestIsNotRetried() async throws {
    // GoTrue's limiters count every attempt and their windows are minutes long, so replaying a
    // 429 within seconds only burns quota.
    let attempts = LockIsolated(0)
    let http = HTTPClient(
      configuration: AuthClient.Configuration(
        url: URL(string: "http://localhost/auth/v1")!,
        localStorage: InMemoryLocalStorage(),
        http: .init(
          transport: ClosureTransport { _, _ in
            attempts.withValue { $0 += 1 }
            return (HTTPTypes.HTTPResponse(status: .tooManyRequests), nil)
          })
      ))

    let (response, _) = try await http.send(
      HTTPTypes.HTTPRequest(method: .post, url: URL(string: "http://localhost/auth/v1/otp")!))

    #expect(response.status == .tooManyRequests)
    #expect(attempts.value == 1)
  }
}
