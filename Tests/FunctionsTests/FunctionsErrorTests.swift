//
//  FunctionsErrorTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 20/01/25.
//

import Foundation
import Functions
import Testing

@Suite
struct FunctionsErrorTests {

  @Test
  func localizedDescription() {
    #expect(
      FunctionsError.relayError.localizedDescription == "Relay Error invoking the Edge Function")
    #expect(
      FunctionsError.httpError(code: 412, data: Data()).localizedDescription
        == "Edge Function returned a non-2xx status code: 412")
  }
}
