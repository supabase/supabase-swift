//
//  ExtractParamsTests.swift
//
//
//  Created by Guilherme Souza on 23/12/23.
//

@testable import Auth
import XCTest

final class ExtractParamsTests: XCTestCase {
  func testExtractParamsInQuery() {
    let code = UUID().uuidString
    let url = URL(string: "io.supabase.flutterquickstart://login-callback/?code=\(code)")!
    let params = extractParams(from: url)
    XCTAssertEqual(params, ["code": code])
  }

  func testExtractParamsInFragment() {
    let code = UUID().uuidString
    let url = URL(string: "io.supabase.flutterquickstart://login-callback/#code=\(code)")!
    let params = extractParams(from: url)
    XCTAssertEqual(params, ["code": code])
  }

  func testExtractParamsInBothFragmentAndQuery() {
    let code = UUID().uuidString
    let url = URL(string: "io.supabase.flutterquickstart://login-callback/?code=\(code)#message=abc")!
    let params = extractParams(from: url)
    XCTAssertEqual(params, ["code": code, "message": "abc"])
  }

  func testExtractParamsQueryTakesPrecedence() {
    let url = URL(string: "io.supabase.flutterquickstart://login-callback/?code=123#code=abc")!
    let params = extractParams(from: url)
    XCTAssertEqual(params, ["code": "123"])
  }
}
