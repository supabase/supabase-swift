//
//  PathEncodingTests.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 25/08/26.
//

import Testing

@testable import HTTPRuntime

@Suite
struct PathEncodingTests {

  @Test
  func pathEncoding() {
    #expect(PathEncoding.segment("a/b c") == "a%2Fb%20c")
    #expect(PathEncoding.greedy("a/b/c.txt") == "a/b/c.txt")
    #expect(PathEncoding.greedy("a/b c.txt") == "a/b%20c.txt")
  }
}
