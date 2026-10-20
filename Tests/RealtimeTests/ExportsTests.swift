//
//  ExportsTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 29/07/25.
//

import Testing

@testable import Realtime

@Suite
struct ExportsTests {
  @Test
  func helperImportIsAccessible() {
    let jsonObject: JSONObject = [:]
    #expect(jsonObject.isEmpty)

    let anyJSON: JSONValue = .string("test")
    #expect(anyJSON == .string("test"))

    _ = ObservationToken {
    }
  }
}
