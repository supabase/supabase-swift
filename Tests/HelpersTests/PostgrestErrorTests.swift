//
//  PostgrestErrorTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 07/05/24.
//

import Foundation
import HTTPTypes
import Testing

@testable import Helpers

@Suite
struct PostgrestErrorTests {
  @Test
  func errorDescriptionIsTheMessage() {
    let error = PostgrestError(kind: .invalidRequest, message: "test error message")

    #expect(error.errorDescription == "test error message")
  }

  @Test
  func serverErrorDecodesTheWirePayload() throws {
    let json = """
      {
        "code": "23505",
        "details": "Key (id)=(1) already exists.",
        "hint": "Use a different id.",
        "message": "duplicate key value violates unique constraint \\"users_pkey\\""
      }
      """

    let payload = try JSONDecoder().decode(PostgrestError.ServerError.self, from: Data(json.utf8))

    #expect(payload.details == "Key (id)=(1) already exists.")
    #expect(payload.hint == "Use a different id.")
    #expect(payload.code == "23505")
    #expect(payload.message == "duplicate key value violates unique constraint \"users_pkey\"")
  }

  @Test
  func descriptionIncludesKindStatusAndRequestID() {
    var headers = HTTPFields()
    headers[.sbRequestID] = "req-9"
    let error = PostgrestError(
      kind: .server,
      message: "Row not found",
      serverError: .init(code: "PGRST116", message: "Row not found"),
      response: HTTPErrorResponse(statusCode: 406, headers: headers, body: Data())
    )

    #expect(
      error.description == "PostgrestError(server): Row not found [status 406, request req-9]")
  }

  @Test
  func matchedZeroRowsReadsTheRowCountFromDetails() {
    #expect(
      PostgrestError.ServerError(
        code: "PGRST116", message: "", details: "The result contains 0 rows"
      ).matchedZeroRows)
    #expect(
      !PostgrestError.ServerError(
        code: "PGRST116", message: "",
        details: "Results contain 2 rows, application/vnd.pgrst.object+json requires 1 row"
      ).matchedZeroRows)
    #expect(!PostgrestError.ServerError(code: "PGRST116", message: "").matchedZeroRows)
  }
}
