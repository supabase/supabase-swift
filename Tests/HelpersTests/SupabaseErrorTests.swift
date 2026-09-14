//
//  SupabaseErrorTests.swift
//  Helpers
//
//  Created by Guilherme Souza on 14/09/26.
//

import Foundation
import HTTPTypes
import Testing

@testable import Helpers

@Suite
struct SupabaseErrorTests {
  private struct FixtureError: SupabaseError {
    var kind: String
    var message: String
    var response: HTTPErrorResponse?
    var underlyingError: (any Error)?
    var description: String { formattedDescription(kind: kind) }
  }

  @Test
  func errorDescriptionDefaultsToMessage() {
    let error = FixtureError(kind: "server", message: "Row not found")

    #expect(error.errorDescription == "Row not found")
    #expect(error.localizedDescription == "Row not found")
  }

  @Test
  func descriptionWithoutResponse() {
    let error = FixtureError(
      kind: "transport", message: "The Internet connection appears to be offline.")

    #expect(
      error.description
        == "FixtureError(transport): The Internet connection appears to be offline.")
  }

  @Test
  func descriptionWithResponseAndRequestID() {
    var headers = HTTPFields()
    headers[.sbRequestID] = "req-1"
    let error = FixtureError(
      kind: "server",
      message: "Row not found",
      response: HTTPErrorResponse(statusCode: 404, headers: headers, body: Data())
    )

    #expect(error.description == "FixtureError(server): Row not found [status 404, request req-1]")
  }

  @Test
  func descriptionWithResponseButNoRequestID() {
    let error = FixtureError(
      kind: "server",
      message: "Row not found",
      response: HTTPErrorResponse(statusCode: 404, headers: HTTPFields(), body: Data())
    )

    #expect(error.description == "FixtureError(server): Row not found [status 404]")
  }

  @Test
  func canBeCaughtAsExistential() {
    let thrown: any Error = FixtureError(kind: "server", message: "boom")

    let caught = thrown as? any SupabaseError
    #expect(caught?.message == "boom")
  }
}
