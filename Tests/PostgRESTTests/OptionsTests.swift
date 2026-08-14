//
//  OptionsTests.swift
//
//
//  Created by Guilherme Souza on 13/08/26.
//

import Testing

@testable import PostgREST

@Suite
struct OptionsTests {
  @Test
  func countOptionStringLiteral() {
    let count: CountOption = "future_count_algorithm"
    #expect(count.rawValue == "future_count_algorithm")
  }

  @Test
  func countOptionHashability() {
    let count1: CountOption = .exact
    let count2: CountOption = "exact"
    #expect(count1 == count2)
  }
}
