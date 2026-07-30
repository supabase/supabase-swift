//
//  CurlCommandTests.swift
//  HTTPRuntimeTestHelpers
//
//  Created by Guilherme Souza on 11/07/26.
//
import Foundation
import HTTPRuntime
import Testing

@testable import HTTPRuntimeTestHelpers

@Suite
struct CurlCommandTests {
  @Test
  func rendersGetWithSortedHeadersAndQuery() {
    let request = HTTPRequest(
      method: .get,
      url: URL(string: "https://example.com/x?b=2&a=1")!,
      headers: ["Content-Type": "application/json", "Accept": "application/json"])
    #expect(
      curlCommand(for: request) == """
        curl \\
        \t--header "Accept: application/json" \\
        \t--header "Content-Type: application/json" \\
        \t"https://example.com/x?a=1&b=2"
        """)
  }

  @Test
  func rendersPostWithEscapedBody() {
    let request = HTTPRequest(
      method: .post,
      url: URL(string: "https://example.com/x")!,
      headers: [:],
      body: .data(Data(#"{"a":1}"#.utf8)))
    #expect(
      curlCommand(for: request) == #"""
        curl \
        	--request POST \
        	--data "{\"a\":1}" \
        	"https://example.com/x"
        """#)
  }

  @Test
  func rendersHead() {
    let request = HTTPRequest(method: .head, url: URL(string: "https://example.com/x")!)
    #expect(
      curlCommand(for: request) == """
        curl \\
        \t--head \\
        \t"https://example.com/x"
        """)
  }
}
