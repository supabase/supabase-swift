//
//  TokenStateTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 06/10/26.
//

import Foundation
import Helpers
import Testing

@testable import Realtime

func makeJWT(exp: TimeInterval?) -> String {
  var claims: [String: Any] = ["role": "authenticated"]
  if let exp { claims["exp"] = exp }
  let header = Base64URL.encode(Data("{\"alg\":\"HS256\"}".utf8))
  let payload = Base64URL.encode(try! JSONSerialization.data(withJSONObject: claims))
  return "\(header).\(payload).sig"
}

@Suite
struct TokenStateTests {
  @Test
  func applyingAResultForTheCurrentGenerationStoresTheTokenAndItsExpiry() {
    var state = TokenState()
    let generation = state.beginRefresh()
    let exp = Date().addingTimeInterval(300).timeIntervalSince1970.rounded()

    let changed = state.apply(makeJWT(exp: exp), generation: generation)

    #expect(changed)
    #expect(state.token == makeJWT(exp: exp))
    #expect(state.expiresAt?.timeIntervalSince1970 == exp)
  }

  @Test
  func aResultFromAnOlderGenerationIsDiscarded() {
    var state = TokenState()
    let first = state.beginRefresh()
    let second = state.beginRefresh()

    let appliedNew = state.apply("new", generation: second)
    let appliedOld = state.apply("old", generation: first)

    #expect(appliedNew)
    #expect(!appliedOld)
    #expect(state.token == "new")
  }

  @Test
  func nilAndUnchangedTokensAreNotChanges() {
    var state = TokenState()
    _ = state.apply("t", generation: state.beginRefresh())

    let appliedNil = state.apply(nil, generation: state.beginRefresh())
    let appliedSame = state.apply("t", generation: state.beginRefresh())

    #expect(!appliedNil)
    #expect(!appliedSame)
    #expect(state.token == "t")
  }

  @Test
  func refreshDelayIsTheLeewayBeforeExpiry() {
    var state = TokenState()
    let now = Date()
    _ = state.apply(
      makeJWT(exp: now.addingTimeInterval(300).timeIntervalSince1970),
      generation: state.beginRefresh())

    #expect(state.refreshDelay(now: now, leeway: .seconds(60)) == .seconds(240))
  }

  @Test
  func refreshDelayIsZeroWhenAlreadyInsideTheLeewayAndNilWithoutExpiry() {
    var state = TokenState()
    let now = Date()
    _ = state.apply(
      makeJWT(exp: now.addingTimeInterval(30).timeIntervalSince1970),
      generation: state.beginRefresh())
    #expect(state.refreshDelay(now: now, leeway: .seconds(60)) == .zero)

    _ = state.apply("opaque", generation: state.beginRefresh())
    #expect(state.refreshDelay(now: now, leeway: .seconds(60)) == nil)
  }
}
