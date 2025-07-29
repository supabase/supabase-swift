//
//  ExportsTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 29/07/25.
//

import XCTest

@testable import Realtime

final class ExportsTests: XCTestCase {
  func testHelperImportIsAccessible() {
    // Test that the Helpers module is properly exported
    // This is a simple validation that the @_exported import works
    
    // Test that we can access JSONObject from Helpers via Realtime
    let jsonObject: JSONObject = [:]
    XCTAssertNotNil(jsonObject)
    
    // Test that we can access AnyJSON from Helpers via Realtime
    let anyJSON: AnyJSON = .string("test")
    XCTAssertEqual(anyJSON, .string("test"))
    
    // Test that we can access ObservationToken from Helpers via Realtime
    let token = ObservationToken {
      // Empty cleanup
    }
    XCTAssertNotNil(token)
  }
}