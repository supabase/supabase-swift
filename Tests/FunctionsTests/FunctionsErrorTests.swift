//
//  FunctionsErrorTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 20/01/25.
//

import Foundation
import Functions
import HTTPTypes
import Helpers
import Testing

@Suite
struct FunctionsErrorTests {
  @Test
  func errorDescriptionIsTheMessage() {
    let error = FunctionsError(kind: .relay, message: "Relay Error invoking the Edge Function")

    #expect(error.localizedDescription == "Relay Error invoking the Edge Function")
    #expect(error.errorDescription == "Relay Error invoking the Edge Function")
  }

  @Test
  func descriptionIncludesKindAndStatus() {
    let error = FunctionsError(
      kind: .server,
      message: "Edge Function returned a non-2xx status code: 412",
      response: HTTPErrorResponse(statusCode: 412, headers: HTTPFields(), body: Data())
    )

    #expect(
      error.description
        == "FunctionsError(server): Edge Function returned a non-2xx status code: 412 [status 412]")
  }

  @Test
  func descriptionAppendsThePlatformCode() {
    let error = FunctionsError(
      kind: .server,
      message: "Edge Function returned a non-2xx status code: 503",
      code: .bootError,
      response: HTTPErrorResponse(statusCode: 503, headers: HTTPFields(), body: Data())
    )

    #expect(
      error.description
        == "FunctionsError(server): Edge Function returned a non-2xx status code: 503 [status 503] [code BOOT_ERROR]"
    )
  }

  @Test
  func isPlatformError() {
    #expect(FunctionsError(kind: .server, message: "", code: .bootError).isPlatformError)
    #expect(FunctionsError(kind: .server, message: "", code: "FUTURE_CODE").isPlatformError)
    #expect(!FunctionsError(kind: .server, message: "", code: .edgeFunctionError).isPlatformError)
    #expect(!FunctionsError(kind: .server, message: "").isPlatformError)
  }

  @Test
  func codeIsOpen() {
    let future = FunctionsError.Code(rawValue: "SOMETHING_NEW")

    #expect(future.rawValue == "SOMETHING_NEW")
    #expect(future != .notFound)
  }

  @Test
  func kindIsOpen() {
    let future = FunctionsError.Kind(rawValue: "somethingNew")

    #expect(future.rawValue == "somethingNew")
    #expect(future != .server)
  }

  @Test
  func conformsToSupabaseError() {
    let error: any Error = FunctionsError(kind: .transport, message: "offline")

    #expect((error as? any SupabaseError)?.message == "offline")
  }
}
