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

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

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

  @Test
  func nonJSONServerErrorUsesStatusCodeAndDescription() async {
    let data = Data("<html><body>proxy failure</body></html>".utf8)
    let error = APIClient.error(
      response: HTTPTypes.HTTPResponse(status: .init(code: 500)), data: data,
      decoder: AuthClient.Configuration.jsonDecoder)

    #expect(error.kind == .server)
    #expect(error.message == "HTTP 500: \(HTTPURLResponse.localizedString(forStatusCode: 500))")
    #expect(error.errorCode == .unexpectedFailure)
    #expect(error.response?.body == data)
  }

  @Test
  func nonJSONServerErrorWithEmptyBodyPreservesStatusCode() async {
    let error = APIClient.error(
      response: HTTPTypes.HTTPResponse(status: .init(code: 503)), data: Data(),
      decoder: AuthClient.Configuration.jsonDecoder)

    #expect(error.message == "HTTP 503: \(HTTPURLResponse.localizedString(forStatusCode: 503))")
  }

  @Test
  func jsonErrorKeepsServerMessage() async {
    let error = APIClient.error(
      response: HTTPTypes.HTTPResponse(status: .init(code: 500)),
      data: Data(#"{"msg":"Error sending confirmation email"}"#.utf8),
      decoder: AuthClient.Configuration.jsonDecoder)

    #expect(error.message == "Error sending confirmation email")
  }

  @Test
  func nonJSONServerErrorUpperBoundaryPreservesStatusCode() async {
    let error = APIClient.error(
      response: HTTPTypes.HTTPResponse(status: .init(code: 599)), data: Data(),
      decoder: AuthClient.Configuration.jsonDecoder)

    #expect(error.message == "HTTP 599: \(HTTPURLResponse.localizedString(forStatusCode: 599))")
  }

  @Test(arguments: [400, 499, 600])
  func nonJSONErrorOutsideServerRangeKeepsExistingFallback(statusCode: Int) async {
    let error = APIClient.error(
      response: HTTPTypes.HTTPResponse(status: .init(code: statusCode)),
      data: Data("<html><body>bad request</body></html>".utf8),
      decoder: AuthClient.Configuration.jsonDecoder)

    #expect(error.message == "Unexpected response with status code \(statusCode).")
  }
}
