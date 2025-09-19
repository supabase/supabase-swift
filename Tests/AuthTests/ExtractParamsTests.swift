//
//  ExtractParamsTests.swift
//
//
//  Created by Guilherme Souza on 23/12/23.
//

import Testing

@testable import Auth

@Suite struct ExtractParamsTests {
  @Test("Extract params from query string")
  func testExtractParamsInQuery() {
    let code = UUID().uuidString
    let url = URL(string: "io.supabase.flutterquickstart://login-callback/?code=\(code)")!
    let params = extractParams(from: url)
    #expect(params == ["code": code])
  }

  @Test("Extract params from fragment")
  func testExtractParamsInFragment() {
    let code = UUID().uuidString
    let url = URL(string: "io.supabase.flutterquickstart://login-callback/#code=\(code)")!
    let params = extractParams(from: url)
    #expect(params == ["code": code])
  }

  @Test("Extract params from both fragment and query")
  func testExtractParamsInBothFragmentAndQuery() {
    let code = UUID().uuidString
    let url = URL(
      string: "io.supabase.flutterquickstart://login-callback/?code=\(code)#message=abc")!
    let params = extractParams(from: url)
    #expect(params == ["code": code, "message": "abc"])
  }

  @Test("Query params take precedence over fragment params")
  func testExtractParamsQueryTakesPrecedence() {
    let url = URL(string: "io.supabase.flutterquickstart://login-callback/?code=123#code=abc")!
    let params = extractParams(from: url)
    #expect(params == ["code": "123"])
  }
}
