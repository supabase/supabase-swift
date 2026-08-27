//
//  CheckStatusTests.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 25/08/26.
//
import Foundation
import HTTPTypes
import Testing

@testable import HTTPRuntime

private struct NotFoundError: APIError, Equatable {
  let message: String
}

private struct CatchAllError: APIError, Equatable {
  let message: String
}

@Suite
struct CheckStatusTests {
  private func response(status: HTTPResponse.Status, json: String) -> HTTPBufferedResponse {
    HTTPBufferedResponse(head: HTTPResponse(status: status), body: Data(json.utf8))
  }

  @Test
  func successfulStatusThrowsNothing() throws {
    let subject = response(status: 200, json: #"{"message":"ignored"}"#)
    try subject.checkStatus(errorTypes: [404: NotFoundError.self], catchAll: CatchAllError.self)
  }

  @Test
  func statusOutsideTwoHundredsIsNotSuccessful() throws {
    let subject = response(status: 302, json: #"{"message":"moved"}"#)
    #expect(throws: CatchAllError(message: "moved")) {
      try subject.checkStatus(errorTypes: [:], catchAll: CatchAllError.self)
    }
  }

  @Test
  func modeledStatusDecodesItsOwnErrorType() throws {
    let subject = response(status: 404, json: #"{"message":"no such row"}"#)
    #expect(throws: NotFoundError(message: "no such row")) {
      try subject.checkStatus(errorTypes: [404: NotFoundError.self], catchAll: CatchAllError.self)
    }
  }

  @Test
  func unmodeledStatusFallsBackToCatchAll() throws {
    let subject = response(status: 500, json: #"{"message":"boom"}"#)
    #expect(throws: CatchAllError(message: "boom")) {
      try subject.checkStatus(errorTypes: [404: NotFoundError.self], catchAll: CatchAllError.self)
    }
  }

  @Test
  func undecodableBodyThrowsUnexpectedResponseCarryingTheBody() throws {
    let subject = response(status: 503, json: "<html>gateway</html>")
    do {
      try subject.checkStatus(errorTypes: [:], catchAll: CatchAllError.self)
      Issue.record("expected checkStatus to throw")
    } catch let error as HTTPRuntimeError {
      guard case .unexpectedResponse(let response, let underlying) = error else {
        Issue.record("expected .unexpectedResponse, got \(error)")
        return
      }
      #expect(response.head.status == 503)
      #expect(response.body == Data("<html>gateway</html>".utf8))
      #expect(underlying != nil)
    }
  }
}
