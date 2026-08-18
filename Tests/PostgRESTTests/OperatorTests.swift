//
//  OperatorTests.swift
//
//
//  Created by Guilherme Souza on 13/08/26.
//

import Testing

@testable import PostgREST

@Suite
struct OperatorTests {
  @Test
  func operatorStringLiteral() {
    let op: PostgrestFilterBuilder.Operator = "future_op"
    #expect(op.rawValue == "future_op")
  }

  @Test
  func operatorHashability() {
    let op1: PostgrestFilterBuilder.Operator = .eq
    let op2: PostgrestFilterBuilder.Operator = "eq"
    #expect(op1 == op2)
  }

  @Test
  func operatorKnownRawValues() {
    let known: [PostgrestFilterBuilder.Operator] = [
      .eq, .neq, .gt, .gte, .lt, .lte, .like, .ilike, .match, .imatch, .is, .isdistinct, .in,
      .cs, .cd, .sl, .sr, .nxl, .nxr, .adj, .ov, .fts, .plfts, .phfts, .wfts,
    ]
    #expect(known.map(\.rawValue).count == Set(known.map(\.rawValue)).count)
  }
}
