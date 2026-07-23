//
//  ExportsTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 29/07/25.
//

import Testing

@testable import Realtime
@testable import RealtimeV2

@Suite
struct ExportsTests {
  @Test
  func helperImportIsAccessible() {
    // Test that the Helpers module is properly exported
    // This is a simple validation that the @_exported import works

    // Test that we can access JSONObject from Helpers via Realtime
    let jsonObject: JSONObject = [:]
    #expect(jsonObject.isEmpty)

    // Test that we can access AnyJSON from Helpers via Realtime
    let anyJSON: AnyJSON = .string("test")
    #expect(anyJSON == .string("test"))

    // Test that we can access ObservationToken from Helpers via Realtime
    _ = ObservationToken {
      // Empty cleanup
    }
  }
}
