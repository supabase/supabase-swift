import Foundation
import Helpers
import Testing

@Suite
struct PostgrestErrorV3BackportTests {
  private let serverError = PostgrestError(
    details: "Key (id)=(1) already exists.",
    hint: "Use a different id.",
    code: "23505",
    message: "duplicate key value"
  )

  @Test
  func serverErrorHoldsTheMessageDetailsAndHint() {
    #expect(
      serverError.serverError
        == PostgrestError.ServerError(
          message: "duplicate key value",
          details: "Key (id)=(1) already exists.",
          hint: "Use a different id."
        )
    )
  }

  @Test
  func serverErrorOfALocalErrorHoldsOnlyTheMessage() {
    let error = PostgrestError(message: "local")

    #expect(error.serverError == PostgrestError.ServerError(message: "local"))
    #expect(error.serverError?.details == nil)
    #expect(error.serverError?.hint == nil)
  }

  @Test
  func codeNamesTheCommonPostgresCodes() {
    let expected: [(PostgrestError.Code, String)] = [
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

    for (code, rawValue) in expected {
      #expect(code.rawValue == rawValue)
    }
  }

  @Test
  func codeRoundTripsAnyValue() {
    let literal: PostgrestError.Code = "PGRST116"

    #expect(literal == PostgrestError.Code(rawValue: "PGRST116"))
    #expect(literal.rawValue == "PGRST116")
  }

  @Test
  func codeMatchesAThrownPostgrestErrorInACatchClause() {
    var matched = false

    do {
      throw serverError
    } catch PostgrestError.Code.foreignKeyViolation {
      Issue.record("Matched the wrong code.")
    } catch PostgrestError.Code.uniqueViolation {
      matched = true
    } catch {
      Issue.record("Did not match the code.")
    }

    #expect(matched)
  }

  @Test
  func codeDoesNotMatchOtherErrors() {
    struct Other: Error {}

    #expect(!(PostgrestError.Code.uniqueViolation ~= Other()))
    #expect(!(PostgrestError.Code.uniqueViolation ~= PostgrestError(message: "no code")))
    #expect("PGRST116" ~= PostgrestError(code: "PGRST116", message: "no rows") as any Error)
  }

  @Test
  func codePropertyIsStillAString() {
    let code: String? = serverError.code

    #expect(code == "23505")
    #expect(PostgrestError.Code.uniqueViolation ~= serverError)
  }

  @Test
  func wireShapeIsUnchanged() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let json = String(decoding: try encoder.encode(serverError), as: UTF8.self)

    #expect(
      json
        == #"{"code":"23505","details":"Key (id)=(1) already exists.","hint":"Use a different id.","message":"duplicate key value"}"#
    )
  }
}

/// A non-SDK error type that a string literal can express, as an app may declare.
private struct AppErrorCode: RawRepresentable, Hashable, Error, ExpressibleByStringLiteral {
  let rawValue: String

  init(rawValue: String) {
    self.rawValue = rawValue
  }

  init(stringLiteral value: String) {
    self.init(rawValue: value)
  }
}

extension PostgrestErrorV3BackportTests {
  @Test
  func codeOperatorDoesNotCaptureStringLiteralPatternsOfOtherErrorTypes() {
    let code = AppErrorCode(rawValue: "not_found")
    var matched = false

    switch code {
    case "not_found": matched = true
    default: break
    }
    if case "other" = code {
      Issue.record("Matched the wrong literal.")
    }

    #expect(matched)
  }

  @Test
  func stringLiteralStillMatchesAPostgrestErrorByCode() {
    let error: any Error = PostgrestError(code: "23505", message: "duplicate")
    var matched = false

    do {
      throw error
    } catch PostgrestError.Code.uniqueViolation {
      matched = true
    } catch {
      Issue.record("Did not match the code.")
    }

    #expect(matched)
    #expect("23505" ~= error)
    #expect(PostgrestError.Code.uniqueViolation ~= error)
  }
}
