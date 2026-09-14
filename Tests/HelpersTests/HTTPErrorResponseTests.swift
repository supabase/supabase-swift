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
    var headerFields = HTTPFields()
    headerFields[.sbRequestID] = "abc"
    headerFields[.contentType] = "application/json"
    let head = HTTPResponse(status: .tooManyRequests, headerFields: headerFields)

    let response = HTTPErrorResponse(head, body: Data("body".utf8))

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
