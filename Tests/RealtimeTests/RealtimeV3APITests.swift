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

@Suite
struct RealtimeChannelConfigurationV3APITests {
  let client = RealtimeClientV2(
    url: URL(string: "http://localhost:54321/realtime/v1")!,
    options: RealtimeClientOptions(headers: ["apikey": "publishable.api.key"])
  )

  @Test
  func defaultConfigurationIsAPublicChannelWithEveryOptionOff() {
    let configuration = RealtimeChannelConfiguration()

    #expect(!configuration.isPrivate)
    #expect(configuration.broadcast == RealtimeChannelConfiguration.Broadcast())
    #expect(configuration.presence == RealtimeChannelConfiguration.Presence())
    #expect(configuration == RealtimeChannelConfiguration())
    #expect(Set([configuration, RealtimeChannelConfiguration()]).count == 1)
  }

  @Test
  func configIsTheSameTypeAsConfiguration() {
    let config: RealtimeChannelConfig = RealtimeChannelConfiguration()
    #expect(config == RealtimeChannelConfiguration())
  }

  @Test
  func broadcastOptionNamesShareStorageWithTheOldNames() {
    var broadcast = RealtimeChannelConfiguration.Broadcast()
    broadcast.receivesOwnMessages = true
    broadcast.acknowledgesMessages = true
    broadcast.waitsForReplication = true

    #expect(broadcast.receiveOwnBroadcasts)
    #expect(broadcast.acknowledgeBroadcasts)
    #expect(broadcast.replicationReady)

    broadcast.receiveOwnBroadcasts = false
    broadcast.acknowledgeBroadcasts = false
    broadcast.replicationReady = false

    #expect(!broadcast.receivesOwnMessages)
    #expect(!broadcast.acknowledgesMessages)
    #expect(!broadcast.waitsForReplication)
  }

  @Test
  func broadcastOptionsKeepTheirWireKeys() throws {
    var broadcast = BroadcastJoinConfig()
    broadcast.receivesOwnMessages = true
    broadcast.waitsForReplication = true

    let data = try JSONEncoder().encode(broadcast)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(json["self"] as? Bool == true)
    #expect(json["ack"] as? Bool == false)
    #expect(json["replication_ready"] as? Bool == true)
    #expect(try JSONDecoder().decode(BroadcastJoinConfig.self, from: data) == broadcast)
  }

  @Test
  func replayTakesADateAndSendsMilliseconds() {
    let replay = RealtimeChannelConfiguration.Broadcast.Replay(
      since: Date(timeIntervalSince1970: 1_700_000_000.5), limit: 10)

    #expect(replay.since == 1_700_000_000_500)
    #expect(replay.limit == 10)
  }

  @Test
  func replayWithAnIntegerLiteralStillTakesMilliseconds() {
    let replay = ReplayOption(since: 1_700_000_000_000)
    let milliseconds: Int = replay.since
    #expect(milliseconds == 1_700_000_000_000)
  }

  @Test
  @MainActor
  func channelConfigureAppliesTheClosure() {
    let channel = client.channel("room") { configuration in
      configuration.isPrivate = true
      configuration.broadcast.receivesOwnMessages = true
      configuration.presence.key = "user-1"
    }

    #expect(channel.configuration.isPrivate)
    #expect(channel.configuration.broadcast.receivesOwnMessages)
    #expect(channel.configuration.presence.key == "user-1")
    #expect(channel.config == channel.configuration)
  }

  @Test
  @MainActor
  func v2ChannelCallSitesKeepTheirMeaning() {
    let plain = client.channel("plain")
    let labelled = client.channel("labelled", options: { $0.isPrivate = true })
    let trailing = client.channel("trailing") { $0.isPrivate = true }
    let sendable: @Sendable (inout RealtimeChannelConfig) -> Void = { $0.isPrivate = true }
    let stored = client.channel("stored", options: sendable)

    #expect(plain.topic == "realtime:plain")
    #expect(!plain.configuration.isPrivate)
    #expect(labelled.configuration.isPrivate)
    #expect(trailing.configuration.isPrivate)
    #expect(stored.configuration.isPrivate)
    #expect(plain.status == .unsubscribed)
    #expect(client.channels.count == 4)
  }
}

@Suite
struct HeartbeatEventV3APITests {
  @Test
  func eventsCompareByValue() {
    #expect(HeartbeatEvent.sent == .sent)
    #expect(
      HeartbeatEvent.acknowledged(latency: .milliseconds(20)) != .acknowledged(latency: .zero))
    #expect(Set<HeartbeatEvent>([.sent, .timedOut, .sent]).count == 2)
  }
}
