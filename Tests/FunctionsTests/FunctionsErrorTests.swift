//
//  FunctionsErrorTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 20/01/25.
//

import Supabase
import XCTest

final class FunctionsErrorTests: XCTestCase {

  func testLocalizedDescription() {
    XCTAssertEqual(FunctionsError.relayError.localizedDescription, "Relay Error invoking the Edge Function")
    XCTAssertEqual(FunctionsError.httpError(code: 412, data: Data()).localizedDescription, "Edge Function returned a non-2xx status code: 412")
  }
}
