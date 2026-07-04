//
//  ExtractParamsTests.swift
//
//
//  Created by Guilherme Souza on 23/12/23.
//

import XCTest

@testable import Auth

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
    let url = URL(
      string: "io.supabase.flutterquickstart://login-callback/?code=\(code)#message=abc")!
    let params = extractParams(from: url)
    XCTAssertEqual(params, ["code": code, "message": "abc"])
  }

  func testExtractParamsQueryTakesPrecedence() {
    let url = URL(string: "io.supabase.flutterquickstart://login-callback/?code=123#code=abc")!
    let params = extractParams(from: url)
    XCTAssertEqual(params, ["code": "123"])
  }

  func testExtractParamsInFragmentWithEqualSignInValue() {
    let url = URL(string: "io.supabase.flutterquickstart://login-callback/#token=abc=&expires=a=b")!
    let params = extractParams(from: url)
    XCTAssertEqual(params, ["token": "abc=", "expires": "a=b"])
  }

  func testExtractParamsInFragmentPercentDecodesValues() {
    let url = URL(
      string:
        "io.supabase.flutterquickstart://login-callback/#error=access_denied&error_description=Invalid%20login%20credentials"
    )!
    let params = extractParams(from: url)
    XCTAssertEqual(
      params,
      ["error": "access_denied", "error_description": "Invalid login credentials"]
    )
  }

  func testExtractParamsInFragmentDecodesPlusAsSpace() {
    let url = URL(
      string:
        "io.supabase.flutterquickstart://login-callback/#error_description=Email+link+is+invalid+or+has+expired"
    )!
    let params = extractParams(from: url)
    XCTAssertEqual(params, ["error_description": "Email link is invalid or has expired"])
  }

  func testExtractParamsInFragmentDecodesAfterSplitting() {
    let url = URL(
      string:
        "io.supabase.flutterquickstart://login-callback/#message=a%26b%3Dc&percent=100%2520off"
    )!
    let params = extractParams(from: url)
    XCTAssertEqual(params, ["message": "a&b=c", "percent": "100%20off"])
  }

  func testExtractParamsInQueryDecodesPlusAsSpace() {
    let url = URL(
      string:
        "io.supabase.flutterquickstart://login-callback/?error_description=Email+link+is+invalid+or+has+expired"
    )!
    let params = extractParams(from: url)
    XCTAssertEqual(params, ["error_description": "Email link is invalid or has expired"])
  }

  func testExtractParamsInQueryDecodesAfterSplitting() {
    let url = URL(
      string:
        "io.supabase.flutterquickstart://login-callback/?message=a%26b%3Dc&percent=100%2520off"
    )!
    let params = extractParams(from: url)
    XCTAssertEqual(params, ["message": "a&b=c", "percent": "100%20off"])
  }

  func testExtractParamsDropsPairsWithoutAValue() {
    let url = URL(string: "io.supabase.flutterquickstart://login-callback/#flag&empty=&code=123")!
    let params = extractParams(from: url)
    XCTAssertEqual(params, ["code": "123"])
  }

  func testExtractParamsDropsBareQueryKeySoErrorFlowIsUnchanged() {
    let url = URL(string: "myapp://callback?error&code=abc123")!
    let params = extractParams(from: url)
    XCTAssertNil(params["error"])
    XCTAssertEqual(params, ["code": "abc123"])
  }

  func testExtractParamsPreservesLiteralPlusEncodedAsPercent2B() {
    let url = URL(
      string:
        "io.supabase.flutterquickstart://login-callback/#error_description=Rate%2Blimit%20exceeded"
    )!
    let params = extractParams(from: url)
    XCTAssertEqual(params, ["error_description": "Rate+limit exceeded"])
  }
}
