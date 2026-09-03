//
//  APIClientTests.swift
//  Supabase
//
//  Created by Muhammadjon Marufov on 02/09/26.
//

import Foundation
import Helpers
import TestHelpers
import Testing

@testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct APIClientTests {
  private let authClient = AuthClient(
    configuration: AuthClient.Configuration(
      url: URL(string: "https://project.supabase.co")!,
      localStorage: InMemoryLocalStorage()
    )
  )

  private var apiClient: APIClient {
    APIClient(clientID: authClient.clientID)
  }

  @Test
  func nonJSONServerErrorUsesStatusCodeAndDescription() async {
    let data = Data("<html><body>proxy failure</body></html>".utf8)
    let response = makeResponse(data: data, statusCode: 500)

    let error = await apiClient.handleError(response: response)

    guard
      case .api(
        let message,
        let errorCode,
        let underlyingData,
        let underlyingResponse
      ) = error
    else {
      Issue.record("Expected an API error, got \(error)")
      return
    }

    #expect(message == "HTTP 500: \(HTTPURLResponse.localizedString(forStatusCode: 500))")
    #expect(errorCode == .unexpectedFailure)
    #expect(underlyingData == data)
    #expect(underlyingResponse === response.underlyingResponse)
  }

  @Test
  func nonJSONServerErrorWithEmptyBodyPreservesStatusCode() async {
    let response = makeResponse(data: Data(), statusCode: 503)

    let error = await apiClient.handleError(response: response)

    #expect(error.message == "HTTP 503: \(HTTPURLResponse.localizedString(forStatusCode: 503))")
  }

  @Test
  func jsonErrorKeepsServerMessage() async {
    let response = makeResponse(
      data: Data(#"{"message":"Error sending confirmation email"}"#.utf8),
      statusCode: 500
    )

    let error = await apiClient.handleError(response: response)

    #expect(error.message == "Error sending confirmation email")
  }

  @Test
  func nonJSONServerErrorUpperBoundaryPreservesStatusCode() async {
    let response = makeResponse(data: Data(), statusCode: 599)

    let error = await apiClient.handleError(response: response)

    #expect(error.message == "HTTP 599: \(HTTPURLResponse.localizedString(forStatusCode: 599))")
  }

  @Test(arguments: [400, 499, 600])
  func nonJSONErrorOutsideServerRangeKeepsExistingFallback(statusCode: Int) async {
    let response = makeResponse(
      data: Data("<html><body>bad request</body></html>".utf8),
      statusCode: statusCode
    )

    let error = await apiClient.handleError(response: response)

    #expect(error.message == "Unexpected error")
  }

  private func makeResponse(data: Data, statusCode: Int) -> HTTPResponse {
    HTTPResponse(
      data: data,
      response: HTTPURLResponse(
        url: URL(string: "https://project.supabase.co/auth/v1/token")!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
      )!
    )
  }
}
