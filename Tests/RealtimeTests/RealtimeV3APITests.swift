//
//  RealtimeV3APITests.swift
//  Supabase
//
//  Tests for the v3 public API that ships on the v2 line. This file imports `Realtime` without
//  `@testable`, so it compiles only against public symbols.
//

import Foundation
import Realtime
import Testing

@Suite
struct RealtimeErrorV3APITests {
  @Test
  func initStoresEveryField() {
    struct Cause: Error {}
    let error = RealtimeError(
      kind: .unauthorized,
      message: "Unauthorized: no access",
      code: .unauthorized,
      underlyingError: Cause()
    )

    #expect(error.kind == .unauthorized)
    #expect(error.message == "Unauthorized: no access")
    #expect(error.code == .unauthorized)
    #expect(error.underlyingError is Cause)
    #expect(error.errorDescription == "Unauthorized: no access")
    #expect((error as any Error).localizedDescription == "Unauthorized: no access")
  }

  @Test
  func kindAndCodeAreOpenStringValues() {
    #expect(RealtimeError.Kind.timeout.rawValue == "timeout")
    #expect(RealtimeError.Kind(rawValue: "future") == "future")
    #expect(RealtimeError.Code.invalidJWTToken.rawValue == "InvalidJWTToken")
    #expect(RealtimeError.Code(rawValue: "Future") == "Future")
  }

  @Test
  func kindMatchesInCatchClause() {
    func run() throws { throw RealtimeError(kind: .timeout, message: "late") }

    var matched = false
    do {
      try run()
    } catch RealtimeError.Kind.unauthorized {
      Issue.record("matched the wrong kind")
    } catch RealtimeError.Kind.timeout {
      matched = true
    } catch {
      Issue.record("did not match: \(error)")
    }
    #expect(matched)
  }

  @Test
  func codeMatchesInCatchClause() {
    func run() throws {
      throw RealtimeError(kind: .server, message: "PrivateOnly: nope", code: .privateOnly)
    }

    var matched = false
    do {
      try run()
    } catch RealtimeError.Code.privateOnly {
      matched = true
    } catch {
      Issue.record("did not match: \(error)")
    }
    #expect(matched)
  }

  @Test
  func patternsDoNotMatchOtherErrors() {
    #expect(!(RealtimeError.Kind.timeout ~= CancellationError()))
    #expect(!(RealtimeError.Code.unauthorized ~= CancellationError()))
  }

  @Test
  func channelClosedByServerHasItsKind() {
    let error = RealtimeError.channelClosedByServer
    #expect(error.kind == .channelClosedByServer)
    #expect(error.errorDescription == "Channel was closed by the server while subscribing.")
  }

  @Test
  func descriptionNamesKindAndMessage() {
    let error = RealtimeError(kind: .decoding, message: "bad frame")
    #expect(error.description == "RealtimeError(decoding): bad frame")
  }
}
