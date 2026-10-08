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

  /// PostgREST answers an ambiguous embed (`PGRST201`) with `details` as an array of candidate
  /// relationships rather than a string. The payload has to survive, because the details and hint
  /// are what tell the caller which foreign-key hint to add.
  @Test
  func serverErrorKeepsStructuredDetails() throws {
    let json = """
      {"code":"PGRST201","message":"Could not embed because more than one relationship was found \
      for 'todos' and 'comments'","details":[{"cardinality":"one-to-many","embedding":"todos with \
      comments","relationship":"comments_todo_id_fkey using todos(id) and comments(todo_id)"}],\
      "hint":"Try changing 'comments' to one of the following: 'comments!comments_todo_id_fkey'."}
      """

    let payload = try JSONDecoder().decode(PostgrestError.ServerError.self, from: Data(json.utf8))

    #expect(payload.code == "PGRST201")
    #expect(payload.details?.contains("comments_todo_id_fkey using todos(id)") == true)
    #expect(payload.hint?.contains("comments!comments_todo_id_fkey") == true)
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
