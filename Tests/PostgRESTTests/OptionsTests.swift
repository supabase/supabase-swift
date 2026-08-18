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

  @Test
  func returningOptionsStringLiteral() {
    let returning: PostgrestReturningOptions = "future_returning_mode"
    #expect(returning.rawValue == "future_returning_mode")
  }

  @Test
  func returningOptionsHashability() {
    let returning1: PostgrestReturningOptions = .minimal
    let returning2: PostgrestReturningOptions = "minimal"
    #expect(returning1 == returning2)
  }

  @Test
  func textSearchTypeStringLiteral() {
    let type: TextSearchType = "future_search_type"
    #expect(type.rawValue == "future_search_type")
  }

  @Test
  func textSearchTypeHashability() {
    let type1: TextSearchType = .plain
    let type2: TextSearchType = "pl"
    #expect(type1 == type2)
  }
}
