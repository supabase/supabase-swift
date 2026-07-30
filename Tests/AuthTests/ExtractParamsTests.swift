//
//  ExtractParamsTests.swift
//
//
//  Created by Guilherme Souza on 23/12/23.
//

import Foundation
import Testing

@testable import Auth

@Suite
struct ExtractParamsTests {
  @Test
  func extractParamsInQuery() {
    let code = UUID().uuidString
    let url = URL(string: "io.supabase.flutterquickstart://login-callback/?code=\(code)")!
    let params = extractParams(from: url)
    #expect(params == ["code": code])
  }

  @Test
  func extractParamsInFragment() {
    let code = UUID().uuidString
    let url = URL(string: "io.supabase.flutterquickstart://login-callback/#code=\(code)")!
    let params = extractParams(from: url)
    #expect(params == ["code": code])
  }

  @Test
  func extractParamsInBothFragmentAndQuery() {
    let code = UUID().uuidString
    let url = URL(
      string: "io.supabase.flutterquickstart://login-callback/?code=\(code)#message=abc")!
    let params = extractParams(from: url)
    #expect(params == ["code": code, "message": "abc"])
  }

  @Test
  func extractParamsQueryTakesPrecedence() {
    let url = URL(string: "io.supabase.flutterquickstart://login-callback/?code=123#code=abc")!
    let params = extractParams(from: url)
    #expect(params == ["code": "123"])
  }

  @Test
  func extractParamsInFragmentWithEqualSignInValue() {
    let url = URL(string: "io.supabase.flutterquickstart://login-callback/#token=abc=&expires=a=b")!
    let params = extractParams(from: url)
    #expect(params == ["token": "abc=", "expires": "a=b"])
  }

  @Test
  func extractParamsInFragmentPercentDecodesValues() {
    let url = URL(
      string:
        "io.supabase.flutterquickstart://login-callback/#error=access_denied&error_description=Invalid%20login%20credentials"
    )!
    let params = extractParams(from: url)
    #expect(
      params == ["error": "access_denied", "error_description": "Invalid login credentials"]
    )
  }

  @Test
  func extractParamsInFragmentDecodesPlusAsSpace() {
    let url = URL(
      string:
        "io.supabase.flutterquickstart://login-callback/#error_description=Email+link+is+invalid+or+has+expired"
    )!
    let params = extractParams(from: url)
    #expect(params == ["error_description": "Email link is invalid or has expired"])
  }

  @Test
  func extractParamsInFragmentDecodesAfterSplitting() {
    let url = URL(
      string:
        "io.supabase.flutterquickstart://login-callback/#message=a%26b%3Dc&percent=100%2520off"
    )!
    let params = extractParams(from: url)
    #expect(params == ["message": "a&b=c", "percent": "100%20off"])
  }

  @Test
  func extractParamsInQueryDecodesPlusAsSpace() {
    let url = URL(
      string:
        "io.supabase.flutterquickstart://login-callback/?error_description=Email+link+is+invalid+or+has+expired"
    )!
    let params = extractParams(from: url)
    #expect(params == ["error_description": "Email link is invalid or has expired"])
  }

  @Test
  func extractParamsInQueryDecodesAfterSplitting() {
    let url = URL(
      string:
        "io.supabase.flutterquickstart://login-callback/?message=a%26b%3Dc&percent=100%2520off"
    )!
    let params = extractParams(from: url)
    #expect(params == ["message": "a&b=c", "percent": "100%20off"])
  }

  @Test
  func extractParamsDropsPairsWithoutAValue() {
    let url = URL(string: "io.supabase.flutterquickstart://login-callback/#flag&empty=&code=123")!
    let params = extractParams(from: url)
    #expect(params == ["code": "123"])
  }

  @Test
  func extractParamsDropsBareQueryKeySoErrorFlowIsUnchanged() {
    let url = URL(string: "myapp://callback?error&code=abc123")!
    let params = extractParams(from: url)
    #expect(params["error"] == nil)
    #expect(params == ["code": "abc123"])
  }

  @Test
  func extractParamsPreservesLiteralPlusEncodedAsPercent2B() {
    let url = URL(
      string:
        "io.supabase.flutterquickstart://login-callback/#error_description=Rate%2Blimit%20exceeded"
    )!
    let params = extractParams(from: url)
    #expect(params == ["error_description": "Rate+limit exceeded"])
  }
}
