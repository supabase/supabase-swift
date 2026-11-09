//
//  PostgrestErrorTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 07/05/24.
//

import Foundation
import HTTPTypes
import Testing

@testable import PostgREST

@Suite
struct PostgrestErrorTests {
  /// Every module re-exports Helpers, so a Helpers type would also show up in `import Storage`.
  @Test
  func isDeclaredInThePostgRESTModule() {
    #expect(String(reflecting: PostgrestError.self) == "PostgREST.PostgrestError")
  }

  @Test
  func isCaughtAsASupabaseError() {
    let error: any Error = PostgrestError(kind: .transport, message: "offline")

    #expect((error as? any SupabaseError)?.message == "offline")
  }

  @Test
  func errorDescriptionIsTheMessage() {
    let error = PostgrestError(kind: .invalidRequest, message: "test error message")

    #expect(error.errorDescription == "test error message")
  }

  private static func serverError(_ json: String, status: HTTPResponse.Status = .conflict)
    -> PostgrestError
  {
    PostgrestError.server(HTTPResponse(status: status), body: Data(json.utf8))
  }

  @Test
  func serverErrorDecodesTheWirePayload() {
    let error = Self.serverError(
      """
      {
        "code": "23505",
        "details": "Key (id)=(1) already exists.",
        "hint": "Use a different id.",
        "message": "duplicate key value violates unique constraint \\"users_pkey\\""
      }
      """)

    #expect(error.kind == .server)
    #expect(error.code == .uniqueViolation)
    #expect(error.message == "duplicate key value violates unique constraint \"users_pkey\"")
    #expect(error.serverError?.details == "Key (id)=(1) already exists.")
    #expect(error.serverError?.hint == "Use a different id.")
    #expect(error.serverError?.message == error.message)
    #expect(error.response?.status == 409)
  }

  @Test
  func serverErrorWithoutACodeHasANilCode() {
    let error = Self.serverError(#"{"message":"boom"}"#, status: .internalServerError)

    #expect(error.code == nil)
    #expect(error.serverError?.message == "boom")
  }

  @Test
  func aBodyThatIsNotAPostgRESTErrorHasNoServerError() {
    let error = Self.serverError("<html>", status: .badGateway)

    #expect(error.kind == .server)
    #expect(error.code == nil)
    #expect(error.serverError == nil)
    #expect(error.message == "Unexpected response with status code 502.")
    #expect(error.response?.body == Data("<html>".utf8))
  }

  /// PostgREST answers an ambiguous embed (`PGRST201`) with `details` as an array of candidate
  /// relationships rather than a string. The payload has to survive, because the details and hint
  /// are what tell the caller which foreign-key hint to add.
  @Test
  func serverErrorKeepsStructuredDetails() {
    let error = Self.serverError(
      """
      {"code":"PGRST201","message":"Could not embed because more than one relationship was found \
      for 'todos' and 'comments'","details":[{"cardinality":"one-to-many","embedding":"todos with \
      comments","relationship":"comments_todo_id_fkey using todos(id) and comments(todo_id)"}],\
      "hint":"Try changing 'comments' to one of the following: 'comments!comments_todo_id_fkey'."}
      """)

    #expect(error.code == "PGRST201")
    #expect(error.serverError?.details?.contains("comments_todo_id_fkey using todos(id)") == true)
    #expect(error.serverError?.hint?.contains("comments!comments_todo_id_fkey") == true)
  }

  static let knownCodes: [(PostgrestError.Code, String)] = [
    (.uniqueViolation, "23505"),
    (.foreignKeyViolation, "23503"),
    (.notNullViolation, "23502"),
    (.checkViolation, "23514"),
    (.invalidTextRepresentation, "22P02"),
    (.insufficientPrivilege, "42501"),
    (.undefinedTable, "42P01"),
    (.undefinedColumn, "42703"),
    (.undefinedFunction, "42883"),
    (.serializationFailure, "40001"),
    (.deadlockDetected, "40P01"),
    (.queryCanceled, "57014"),
    (.raiseException, "P0001"),
  ]

  @Test(arguments: knownCodes)
  func knownCodesHaveTheirSQLSTATE(code: PostgrestError.Code, raw: String) {
    #expect(code.rawValue == raw)
    #expect(code == PostgrestError.Code(rawValue: raw))
  }

  @Test
  func catchMatchesKindAndCode() {
    let error: any Error = PostgrestError(kind: .server, message: "dup", code: .uniqueViolation)

    #expect(PostgrestError.Kind.server ~= error)
    #expect(!(PostgrestError.Kind.transport ~= error))
    #expect(PostgrestError.Code.uniqueViolation ~= error)
    #expect(!(PostgrestError.Code.foreignKeyViolation ~= error))
    #expect(!(PostgrestError.Code.uniqueViolation ~= URLError(.timedOut)))
    #expect(!(PostgrestError.Kind.server ~= URLError(.timedOut)))

    do {
      throw error
    } catch PostgrestError.Code.uniqueViolation {
    } catch {
      Issue.record("Expected PostgrestError.Code.uniqueViolation, got \(error)")
    }
  }

  @Test
  func descriptionIncludesKindStatusAndRequestID() {
    var headers = HTTPFields()
    headers[.sbRequestID] = "req-9"
    let error = PostgrestError(
      kind: .server,
      message: "Row not found",
      code: "PGRST116",
      serverError: .init(message: "Row not found"),
      response: HTTPErrorResponse(status: 406, headers: headers, body: Data())
    )

    #expect(
      error.description
        == "PostgrestError(server): Row not found [status 406, request req-9] [code PGRST116]")
  }

  @Test
  func matchedZeroRowsReadsTheRowCountFromDetails() {
    #expect(
      PostgrestError.ServerError(message: "", details: "The result contains 0 rows").matchedZeroRows
    )
    #expect(
      !PostgrestError.ServerError(
        message: "",
        details: "Results contain 2 rows, application/vnd.pgrst.object+json requires 1 row"
      ).matchedZeroRows)
    #expect(!PostgrestError.ServerError(message: "").matchedZeroRows)
  }
}
