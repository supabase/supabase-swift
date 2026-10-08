//
//  RealtimeClientTests.swift
//  Realtime
//
//  Created by Guilherme Souza on 08/10/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import Helpers
import IssueReporting
import TestHelpers
import Testing

#if canImport(UIKit)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

@testable import Realtime

@Suite(.timeLimit(.minutes(1)))
struct RealtimeClientTests {
  let clock = TestClock()
  let server: FakeRealtimeServer

  init() {
    server = FakeRealtimeServer(clock: clock)
  }

  private func makeClient(
    configure: (inout RealtimeClientOptions) -> Void = { _ in }
  ) -> RealtimeClient {
    var options = RealtimeClientOptions()
    options.webSocketTransport = server.transport
    options.clock = clock
    options.handleAppLifecycle = false
    options.headers[.apikey] = "test-key"
    configure(&options)
    return RealtimeClient(
      url: URL(string: "http://localhost:54321/realtime/v1")!, options: options)
  }

  private var joins: [RealtimeMessageV2] { server.sentMessages.filter { $0.event == "phx_join" } }

  /// A sleeper reaches the clock only once its task has run, and an advance made before that
  /// strands it.
  private func settle() async {
    for _ in 0..<1_000 { await Task.yield() }
  }

  // MARK: - Connection

  @Test
  func connectThrowsUnauthorizedWhenTheUpgradeIsRefused() async {
    let client = makeClient()
    server.refuseNextUpgrade(status: 401)

    await #expect {
      try await client.connect()
    } throws: { error in
      (error as? RealtimeError)?.kind == .unauthorized
    }
    #expect(client.status.error?.kind == .unauthorized)
  }

  @Test
  func disconnectClosesTheSocketAndReportsDisconnected() async throws {
    let client = makeClient()
    try await client.connect()
    #expect(client.status.isConnected)

    await client.disconnect()

    guard case .disconnected(nil) = client.status else {
      Issue.record("expected .disconnected(nil), got \(client.status)")
      return
    }
    #expect(!server.isConnected)
  }

  @Test
  func statusChangesStartsWithTheCurrentStatus() async throws {
    let client = makeClient()
    var statuses = client.statusChanges.makeAsyncIterator()

    guard case .disconnected(nil)? = await statuses.next() else {
      Issue.record("expected the current status first")
      return
    }
    try await client.connect()
    #expect(await statuses.next()?.isConnected == true)
  }

  @Test
  func pauseThenResumeRejoinsASubscribedChannel() async throws {
    let client = makeClient()
    let channel = client.channel("room")
    try await channel.subscribe()

    await client.pause()
    #expect(!client.status.isConnected)
    #expect(!server.isConnected)

    await client.resume()

    #expect(await waitUntil { channel.status.isSubscribed })
    #expect(joins.count == 2)
  }

  @Test
  func heartbeatsForwardsTheEngineEvents() async throws {
    let client = makeClient { $0.heartbeatInterval = .seconds(1) }
    let heartbeats = client.heartbeats
    try await client.connect()
    let collected = Task {
      var events: [HeartbeatEvent] = []
      for await event in heartbeats {
        events.append(event)
        if events.count == 2 { break }
      }
      return events
    }

    await settle()
    await clock.advance(by: .seconds(1))

    let events = await collected.value
    #expect(events.first == .sent)
    guard case .acknowledged? = events.last else {
      Issue.record("expected an acknowledgement, got \(events)")
      return
    }
  }

  // MARK: - URL and headers

  @Test
  func upgradeCarriesTheAPIKeyTheLogLevelAndTheClientInfo() async throws {
    let client = makeClient { $0.serverLogLevel = .warning }
    try await client.connect()

    let url = try #require(server.upgradeURL)
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(url.scheme == "ws")
    #expect(url.path == "/realtime/v1/websocket")
    #expect(query.contains(URLQueryItem(name: "log_level", value: "warning")))
    #expect(query.contains(URLQueryItem(name: "apikey", value: "test-key")))
    #expect(server.upgradeHeaders[.xClientInfo]?.hasPrefix("realtime-swift/") == true)
  }

  @Test
  func noServerLogLevelLeavesItOutOfTheURL() async throws {
    let client = makeClient()
    try await client.connect()

    let url = try #require(server.upgradeURL)
    #expect(url.query?.contains("log_level") == false)
  }

  @Test
  func aCustomClientInfoHeaderIsKept() async throws {
    let client = makeClient { $0.headers[.xClientInfo] = "my-app/1.0" }
    try await client.connect()

    #expect(server.upgradeHeaders[.xClientInfo] == "my-app/1.0")
  }

  // MARK: - Channels

  @Test
  func channelReturnsTheSameInstanceForATopic() {
    let client = makeClient()

    let first = client.channel("room")
    let second = client.channel("room")

    #expect(first === second)
    #expect(client.channel("other") !== first)
  }

  @Test
  func channelWithADifferentConfigurationReportsAnIssueAndKeepsTheFirst() {
    let client = makeClient()
    let first = client.channel("room")

    withExpectedIssue {
      let second = client.channel("room") { $0.isPrivate = true }
      #expect(second === first)
    }
    #expect(!first.configuration.isPrivate)
  }

  @Test
  func channelsListsEveryChannel() {
    let client = makeClient()
    let room = client.channel("room")
    let lobby = client.channel("lobby")

    let channels = client.channels

    #expect(channels.count == 2)
    #expect(channels.contains { $0 === room })
    #expect(channels.contains { $0 === lobby })
  }

  @Test
  func removeChannelLeavesAndForgetsTheChannel() async throws {
    let client = makeClient()
    let channel = client.channel("room")
    try await channel.subscribe()

    await client.removeChannel(channel)

    #expect(server.sentMessages.contains { $0.event == "phx_leave" && $0.topic == "realtime:room" })
    #expect(client.channels.isEmpty)
    #expect(client.channel("room") !== channel)
  }

  @Test
  func removeAllChannelsLeavesEveryChannel() async throws {
    let client = makeClient()
    let room = client.channel("room")
    let lobby = client.channel("lobby")
    try await room.subscribe()
    try await lobby.subscribe()

    await client.removeAllChannels()

    let leaves = Set(server.sentMessages.filter { $0.event == "phx_leave" }.map(\.topic))
    #expect(leaves == ["realtime:room", "realtime:lobby"])
    #expect(client.channels.isEmpty)
  }

  @Test
  func setAuthSendsTheTokenOnTheNextJoin() async throws {
    let client = makeClient()
    await client.setAuth("user-token")

    try await client.channel("room").subscribe()

    #expect(joins.last?.payload["access_token"] == "user-token")
  }

  #if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
    @Test
    func comingToTheForegroundReconnectsWithoutWaitingOutTheBackoff() async throws {
      let client = makeClient {
        $0.handleAppLifecycle = true
        $0.reconnect = .steps([.seconds(60)])
      }
      try await client.connect()
      server.closeConnection(code: .goingAway, reason: nil)
      #expect(await waitUntil { if case .reconnecting = client.status { true } else { false } })

      #if canImport(UIKit)
        NotificationCenter.default.post(
          name: UIApplication.willEnterForegroundNotification, object: nil)
      #else
        NotificationCenter.default.post(
          name: NSApplication.willBecomeActiveNotification, object: nil)
      #endif

      #expect(await waitUntil { client.status.isConnected })
      #expect(server.connectCount == 2)
    }
  #endif

  // MARK: - Lifetime

  @Test
  func droppingTheClientAndItsChannelsClosesTheSocket() async throws {
    do {
      let client = makeClient()
      let channel = client.channel("room")
      try await channel.subscribe()
      #expect(server.isConnected)
    }

    #expect(await waitUntil { !server.isConnected })
  }

  @Test
  func droppingTheClientClosesTheSocketEvenWhileAChannelHandleLives() async throws {
    let channel: RealtimeChannel
    do {
      let client = makeClient()
      channel = client.channel("room")
      try await channel.subscribe()
    }

    #expect(await waitUntil { !server.isConnected })
    #expect(await waitUntil { !channel.status.isSubscribed })
    await #expect(throws: RealtimeError.self) { try await channel.subscribe() }
    #expect(!server.isConnected)
  }
}
