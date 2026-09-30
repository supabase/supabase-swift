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
      kind: .http,
      message: "Edge Function returned a non-2xx status code: 412",
      response: HTTPErrorResponse(statusCode: 412, headers: HTTPFields(), body: Data())
    )

    #expect(
      error.description
        == "FunctionsError(http): Edge Function returned a non-2xx status code: 412 [status 412]")
  }

  @Test
  func kindIsOpen() {
    let future = FunctionsError.Kind(rawValue: "somethingNew")

    #expect(future.rawValue == "somethingNew")
    #expect(future != .http)
  }

  @Test
  func conformsToSupabaseError() {
    let error: any Error = FunctionsError(kind: .transport, message: "offline")

    #expect((error as? any SupabaseError)?.message == "offline")
  }
}
