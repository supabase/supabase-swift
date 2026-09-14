//
//  HTTPErrorResponseTests.swift
//  Helpers
//
//  Created by Guilherme Souza on 14/09/26.
//

import Foundation
import HTTPTypes
import Testing

@testable import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct HTTPErrorResponseTests {
  @Test
  func requestIDReadsTheSupabaseHeader() {
    var headers = HTTPFields()
    headers[.sbRequestID] = "019b1e49-6e1a-7556-92dc-909063bc3313"
    let response = HTTPErrorResponse(statusCode: 404, headers: headers, body: Data())

    #expect(response.requestID == "019b1e49-6e1a-7556-92dc-909063bc3313")
  }

  @Test
  func requestIDIsNilWithoutTheHeader() {
    let response = HTTPErrorResponse(statusCode: 500, headers: HTTPFields(), body: Data())

    #expect(response.requestID == nil)
  }

  @Test
  func initFromHTTPResponseCopiesStatusHeadersAndBody() throws {
    let urlResponse = try #require(
      HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 429,
        httpVersion: nil,
        headerFields: ["sb-request-id": "abc", "Content-Type": "application/json"]
      )
    )
    let http = HTTPResponse(data: Data("body".utf8), response: urlResponse)

    let response = HTTPErrorResponse(http)

    #expect(response.statusCode == 429)
    #expect(response.body == Data("body".utf8))
    #expect(response.requestID == "abc")
    #expect(response.headers[.contentType] == "application/json")
  }

  @Test
  func isHashable() {
    let a = HTTPErrorResponse(statusCode: 400, headers: HTTPFields(), body: Data("x".utf8))
    let b = HTTPErrorResponse(statusCode: 400, headers: HTTPFields(), body: Data("x".utf8))

    #expect(a == b)
    #expect(Set([a, b]).count == 1)
  }
}
