//
//  PostgrestFilterOperatorTests.swift
//  Supabase
//
//  Created by Lukas Klingsbo on 08/09/26.
//

import Testing

@testable import PostgREST

@Suite
struct PostgrestFilterOperatorTests {
  @Test
  func everyOperatorRendersItsToken() {
    let tokens: [(PostgrestFilterOperator, String)] = [
      (.eq, "eq"), (.neq, "neq"), (.gt, "gt"), (.gte, "gte"), (.lt, "lt"), (.lte, "lte"),
      (.is, "is"), (.isDistinct, "isdistinct"), (.in, "in"),
      (.like, "like"), (.ilike, "ilike"),
      (.likeAllOf, "like(all)"), (.likeAnyOf, "like(any)"),
      (.ilikeAllOf, "ilike(all)"), (.ilikeAnyOf, "ilike(any)"),
      (.regexMatch, "match"), (.regexIMatch, "imatch"),
      (.contains, "cs"), (.containedBy, "cd"), (.overlaps, "ov"),
      (.rangeLt, "sl"), (.rangeGt, "sr"), (.rangeGte, "nxl"), (.rangeLte, "nxr"),
      (.rangeAdjacent, "adj"),
      (.textSearch(config: nil, type: nil), "fts"),
    ]
    for (op, token) in tokens {
      #expect(op.token == token)
    }
  }

  /// The conversion prefix goes in front of `fts` and the configuration behind it, so the whole
  /// operator is one token and no separate node is needed for text search.
  @Test
  func textSearchFoldsItsTypeAndConfigIntoTheToken() {
    #expect(
      PostgrestFilterOperator.textSearch(config: "english", type: nil).token == "fts(english)")
    #expect(PostgrestFilterOperator.textSearch(config: nil, type: .plain).token == "plfts")
    #expect(PostgrestFilterOperator.textSearch(config: nil, type: .phrase).token == "phfts")
    #expect(
      PostgrestFilterOperator.textSearch(config: "english", type: .websearch).token
        == "wfts(english)")
  }
}
