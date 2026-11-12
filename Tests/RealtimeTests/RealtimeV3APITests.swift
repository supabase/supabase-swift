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

@Suite
struct RealtimeRenamesV3APITests {
  @Test
  func postgresColumnIsAMutableHashableValue() {
    var column = PostgresColumn(name: "id", type: "int8")
    column.type = "uuid"

    #expect(column.name == "id")
    #expect(Set([column, column]).count == 1)
  }

  @Test
  func columnIsTheSameTypeAsPostgresColumn() {
    let column: Column = PostgresColumn(name: "id", type: "int8")
    #expect(column == PostgresColumn(name: "id", type: "int8"))
  }

  @Test
  func serverLogLevelKeepsTheWireValues() {
    #expect(RealtimeServerLogLevel.warning == .warn)
    #expect(RealtimeServerLogLevel.warning.rawValue == "warn")
    #expect(RealtimeServerLogLevel.info.rawValue == "info")
    #expect(RealtimeServerLogLevel.error.rawValue == "error")

    let level: LogLevel = RealtimeServerLogLevel.info
    _ = RealtimeClientOptions(logLevel: level)
  }

  @Test
  func observesAppLifecycleIsTheSameSettingAsHandleAppLifecycle() {
    var options = RealtimeClientOptions(handleAppLifecycle: true)
    #expect(options.observesAppLifecycle)

    options.observesAppLifecycle = false
    #expect(!options.handleAppLifecycle)

    options.handleAppLifecycle = true
    #expect(options.observesAppLifecycle)

    #expect(
      RealtimeClientOptions.defaultObservesAppLifecycle
        == RealtimeClientOptions.defaultHandleAppLifecycle)
    #expect(
      RealtimeClientOptions().observesAppLifecycle
        == RealtimeClientOptions.defaultObservesAppLifecycle)
  }

  @Test
  func defaultConnectsOnSubscribeMatchesTheOldName() {
    #expect(
      RealtimeClientOptions.defaultConnectsOnSubscribe
        == RealtimeClientOptions.defaultConnectOnSubscribe)
  }

  @Test
  func statusPredicates() {
    #expect(RealtimeClientStatus.connected.isConnected)
    #expect(!RealtimeClientStatus.connecting.isConnected)
    #expect(!RealtimeClientStatus.disconnected.isConnected)

    #expect(RealtimeChannelStatus.subscribed.isSubscribed)
    #expect(!RealtimeChannelStatus.subscribing.isSubscribed)
    #expect(!RealtimeChannelStatus.unsubscribed.isSubscribed)
    #expect(!RealtimeChannelStatus.unsubscribing.isSubscribed)
  }

  @Test
  func realtimeFilterValueReadsRawValue() {
    struct Slug: RealtimePostgresFilterValue {
      var rawValue: String { "a-slug" }
    }

    #expect("text".realtimeFilterValue == "text")
    #expect(5.realtimeFilterValue == "5")
    #expect(true.realtimeFilterValue == "true")
    #expect(Slug().realtimeFilterValue == "a-slug")
  }
}
