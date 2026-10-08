//
//  RealtimeClientTests.swift
//  Realtime
//
//  Created by Guilherme Souza on 08/10/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import HTTPTypes
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
  func pauseWhileConnectingKeepsTheChannelWantingItsSubscription() async throws {
    struct HangingTransport: WebSocketTransport {
      func connect(to url: URL, headerFields: HTTPFields) async throws -> any WebSocketConnection {
        try await Task.sleep(for: .seconds(3_600))
        throw CancellationError()
      }
    }
    let client = makeClient { $0.webSocketTransport = HangingTransport() }
    let channel = client.channel("room")
    let subscription = Task { try await channel.subscribe() }
    defer { subscription.cancel() }
    #expect(await waitUntil { if case .connecting = client.status { true } else { false } })

    // Cancels the supervisor mid-connect; its exit must not unsubscribe the channel.
    await client.pause()
    await settle()

    guard case .subscribing = channel.status else {
      Issue.record("expected the channel to still want its subscription, got \(channel.status)")
      return
    }
  }

  @Test
  func cancellingConnectThrowsCancellationAndLeavesOtherCallersWaiting() async throws {
    struct HangingTransport: WebSocketTransport {
      func connect(to url: URL, headerFields: HTTPFields) async throws -> any WebSocketConnection {
        try await Task.sleep(for: .seconds(3_600))
        throw CancellationError()
      }
    }
    let client = makeClient { $0.webSocketTransport = HangingTransport() }
    let cancelledError = LockIsolated<(any Error)?>(nil)
    let otherReturned = LockIsolated(false)
    let cancelled = Task {
      do { try await client.connect() } catch { cancelledError.setValue(error) }
    }
    let other = Task {
      try? await client.connect()
      otherReturned.setValue(true)
    }
    defer { other.cancel() }
    #expect(await waitUntil { if case .connecting = client.status { true } else { false } })
    await settle()

    cancelled.cancel()

    #expect(await waitUntil(timeout: 2) { cancelledError.value is CancellationError })
    await settle()
    #expect(!otherReturned.value)
    guard case .connecting = client.status else {
      Issue.record("expected the client to keep connecting, got \(client.status)")
      return
    }
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

  @Test
  func removingAStaleHandleKeepsTheNewChannel() async throws {
    let client = makeClient()
    let stale = client.channel("room")
    try await stale.subscribe()
    await client.removeChannel(stale)
    let current = client.channel("room")
    try await current.subscribe()

    await client.removeChannel(stale)

    #expect(current.status.isSubscribed)
    #expect(client.channels.contains { $0 === current })
    #expect(server.sentMessages.filter { $0.event == "phx_leave" }.count == 1)
  }

  @Test
  func aChannelMadeWhileTheOldOneIsLeavingKeepsItsSubscription() async throws {
    let client = makeClient()
    let old = client.channel("room")
    let oldEvents = old.events
    let oldStatuses = old.statusChanges
    try await old.subscribe()
    server.dropsClientFrames = true
    let removal = Task { await client.removeChannel(old) }
    #expect(await waitUntil { if case .unsubscribing = old.status { true } else { false } })

    let new = client.channel("room")
    let subscription = Task { try await new.subscribe() }
    await settle()
    server.dropsClientFrames = false
    await clock.advance(by: .seconds(15))
    await removal.value

    try await subscription.value
    #expect(new.status.isSubscribed)
    #expect(client.channels.contains { $0 === new })
    #expect(await hasFinished(oldEvents))
    #expect(await hasFinished(oldStatuses))
  }

  @Test
  func cancellingSubscribeThrowsCancellationAndLeavesOtherCallersWaiting() async throws {
    let client = makeClient { $0.rejoin = .steps([.seconds(1)]) }
    let channel = client.channel("room")
    server.joinReply = .silent
    let cancelledError = LockIsolated<(any Error)?>(nil)
    let otherReturned = LockIsolated(false)
    let cancelled = Task {
      do { try await channel.subscribe() } catch { cancelledError.setValue(error) }
    }
    let other = Task {
      try await channel.subscribe()
      otherReturned.setValue(true)
    }
    defer { other.cancel() }
    #expect(await waitUntil { joins.count == 1 })
    await settle()

    cancelled.cancel()

    #expect(await waitUntil(timeout: 2) { cancelledError.value is CancellationError })
    guard case .subscribing = channel.status else {
      Issue.record("expected the channel to keep wanting its subscription, got \(channel.status)")
      return
    }
    #expect(!otherReturned.value)
    server.joinReply = .ok
    await clock.advance(by: .seconds(15))
    await settle()
    await clock.advance(by: .seconds(1))
    #expect(await waitUntil(timeout: 2) { otherReturned.value })
  }

  @Test
  func concurrentUnsubscribesBothReturnWhenTheLeaveTimesOut() async throws {
    let client = makeClient()
    let channel = client.channel("room")
    try await channel.subscribe()
    server.dropsClientFrames = true
    let returned = LockIsolated(0)

    for _ in 0..<2 {
      Task {
        await channel.unsubscribe()
        returned.withValue { $0 += 1 }
      }
    }
    await settle()
    await clock.advance(by: .seconds(15))

    #expect(await waitUntil(timeout: 2) { returned.value == 2 })
  }

  @Test(arguments: [false, true])
  func unsubscribeRacingRemoveChannelBothReturnAndTheTopicCanBeReused(removeFirst: Bool)
    async throws
  {
    let client = makeClient()
    let channel = client.channel("room")
    try await channel.subscribe()
    server.dropsClientFrames = true
    let returned = LockIsolated(0)
    let calls: [@Sendable () async -> Void] = [
      { await channel.unsubscribe() }, { await client.removeChannel(channel) },
    ]

    for call in removeFirst ? calls.reversed() : calls {
      Task {
        await call()
        returned.withValue { $0 += 1 }
      }
      await settle()
    }
    server.dropsClientFrames = false
    await clock.advance(by: .seconds(15))

    #expect(await waitUntil(timeout: 2) { returned.value == 2 })
    // A detached wait: a hung `addChannel` ignores cancellation, so `withTimeout` would hang too.
    let next = client.channel("room")
    Task { try await next.subscribe() }
    #expect(await waitUntil(timeout: 2) { next.status.isSubscribed })
  }

  @Test
  func aRemovedHandleCannotSubscribeOrTouchTheLiveChannel() async throws {
    let client = makeClient { $0.reconnect = .steps([.seconds(1)]) }
    let old = client.channel("room")
    try await old.subscribe()
    await client.removeChannel(old)
    let live = client.channel("room") { $0.broadcast.acknowledge = true }
    try await live.subscribe()
    let joinCount = joins.count

    await #expect {
      try await old.subscribe()
    } throws: { error in
      (error as? RealtimeError)?.kind == .notSubscribed
    }
    await old.unsubscribe()

    #expect(joins.count == joinCount)
    #expect(live.status.isSubscribed)
    guard case .unsubscribed = old.status else {
      Issue.record("expected the removed handle to read .unsubscribed, got \(old.status)")
      return
    }
    // The next join still carries the live channel's config, not the removed handle's.
    server.closeConnection(code: .goingAway, reason: nil)
    await settle()
    await clock.advance(by: .seconds(1))
    #expect(await waitUntil { joins.count == joinCount + 1 })
    let config = joins.last?.payload["config"]?.objectValue
    #expect(config?["broadcast"]?.objectValue?["ack"] == true)
  }

  @Test
  func streamsMadeOnARemovedHandleFinish() async throws {
    let client = makeClient()
    let channel = client.channel("room")
    try await channel.subscribe()
    await client.removeChannel(channel)

    #expect(await hasFinished(channel.broadcasts(event: "ping")))
    #expect(await hasFinished(channel.events))
    #expect(await hasFinished(channel.statusChanges))
    #expect(await hasFinished(channel.presence.states))
  }

  @Test
  func aRemovedHandleStatusStreamEndsOnUnsubscribed() async throws {
    let client = makeClient()
    let channel = client.channel("room")
    try await channel.subscribe()
    await client.removeChannel(channel)

    let stream = channel.statusChanges
    let statuses = try await withTimeout(.seconds(2)) {
      var statuses: [RealtimeChannelStatus] = []
      for await status in stream { statuses.append(status) }
      return statuses
    }

    guard statuses.count == 1, case .unsubscribed = statuses[0] else {
      Issue.record("expected only .unsubscribed, got \(statuses)")
      return
    }
  }

  @Test
  func aRemovedHandleCannotSendOnTheLiveChannel() async throws {
    let client = makeClient()
    let old = client.channel("room")
    try await old.subscribe()
    await client.removeChannel(old)
    try await client.channel("room").subscribe()
    let sentCount = server.sentFrames.count

    await #expect {
      try await old.broadcast(event: "ping", payload: ["n": 1])
    } throws: { error in
      (error as? RealtimeError)?.kind == .notSubscribed
    }
    await #expect {
      try await old.broadcast(event: "blob", data: Data([1]))
    } throws: { error in
      (error as? RealtimeError)?.kind == .notSubscribed
    }
    await #expect {
      try await old.presence.track(["name": "ana"])
    } throws: { error in
      (error as? RealtimeError)?.kind == .notSubscribed
    }
    await #expect {
      try await old.presence.untrack()
    } throws: { error in
      (error as? RealtimeError)?.kind == .notSubscribed
    }

    #expect(server.sentFrames.count == sentCount)
  }

  @Test
  func presenceStartsEmptyForAChannelThatReplacesARemovedOne() async throws {
    let client = makeClient()
    let old = client.channel("room")
    try await old.subscribe()
    server.pushPresenceState(topic: "realtime:room", state: ["u1": ["metas": [["phx_ref": "r1"]]]])
    #expect(await waitUntil { !old.presence.state.entries.isEmpty })

    await client.removeChannel(old)
    let new = client.channel("room")
    try await new.subscribe()

    #expect(new.presence.state.entries.isEmpty)
    #expect(old.presence.state.entries.isEmpty)
    server.pushPresenceState(topic: "realtime:room", state: ["u2": ["metas": [["phx_ref": "r2"]]]])
    #expect(await waitUntil { new.presence.state.entries.keys.sorted() == ["u2"] })
    #expect(old.presence.state.entries.isEmpty)
  }

  // MARK: - Auth

  @Test
  func setAuthWithNilAsksTheProviderAgain() async throws {
    let calls = LockIsolated(0)
    let client = makeClient {
      $0.accessToken = {
        calls.withValue { $0 += 1 }
        return "token-\(calls.value)"
      }
    }
    try await client.channel("room").subscribe()
    #expect(joins.last?.payload["access_token"] == "token-1")

    await client.setAuth(nil)

    #expect(
      await waitUntil {
        server.sentMessages.contains {
          $0.event == "access_token" && $0.payload["access_token"] == "token-2"
        }
      })
  }

  @Test
  func setAuthWithNilAndNoProviderKeepsTheToken() async throws {
    let client = makeClient()
    await client.setAuth("manual")
    await client.setAuth(nil)

    try await client.channel("room").subscribe()

    #expect(joins.last?.payload["access_token"] == "manual")
  }

  @Test
  func theAuthorizationHeaderGivesTheFirstToken() async throws {
    let client = makeClient { $0.headers[.authorization] = "Bearer seeded" }

    try await client.channel("room").subscribe()

    #expect(joins.last?.payload["access_token"] == "seeded")
  }

  @Test
  func theProviderOverridesTheAuthorizationHeader() async throws {
    let client = makeClient {
      $0.headers[.authorization] = "Bearer seeded"
      $0.accessToken = { "provided" }
    }

    try await client.channel("room").subscribe()

    #expect(joins.last?.payload["access_token"] == "provided")
  }

  @Test
  func httpSendThrowsTheProviderError() async throws {
    struct ProviderFailed: Error {}
    let http = RecordingTransport()
    http.respond { _, _ in (HTTPResponse(status: .init(code: 202)), Data()) }
    let client = makeClient {
      $0.http = HTTPClientConfiguration(transport: http)
      $0.accessToken = { throw ProviderFailed() }
    }

    await #expect(throws: ProviderFailed.self) {
      try await client.channel("room").httpSend(event: "ping", payload: ["n": 1])
    }
    #expect(http.requests.isEmpty)
  }

  @Test
  func httpSendFallsBackToTheAPIKeyWithoutAProviderOrToken() async throws {
    let http = RecordingTransport()
    http.respond { _, _ in (HTTPResponse(status: .init(code: 202)), Data()) }
    let client = makeClient { $0.http = HTTPClientConfiguration(transport: http) }

    try await client.channel("room").httpSend(event: "ping", payload: ["n": 1])

    #expect(http.requests.first?.head.headerFields[.authorization] == "Bearer test-key")
  }

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

  @Test
  func droppingTheClientFinishesEveryStream() async throws {
    let channel: RealtimeChannel
    let heartbeats: RealtimeStream<HeartbeatEvent>
    let statuses: RealtimeStream<RealtimeConnectionStatus>
    let channelStatuses: RealtimeStream<RealtimeChannelStatus>
    let events: RealtimeStream<RealtimeChannelEvent>
    do {
      let client = makeClient()
      heartbeats = client.heartbeats
      statuses = client.statusChanges
      channel = client.channel("room")
      channelStatuses = channel.statusChanges
      events = channel.events
      try await channel.subscribe()
    }

    #expect(await hasFinished(heartbeats))
    #expect(await hasFinished(statuses))
    #expect(await hasFinished(channelStatuses))
    #expect(await hasFinished(events))
    #expect(await hasFinished(channel.broadcasts(event: "ping")))
    #expect(await hasFinished(channel.statusChanges))
  }
}

/// Whether `stream` ends within two seconds.
func hasFinished<Element>(_ stream: RealtimeStream<Element>) async -> Bool {
  let finished = LockIsolated(false)
  let drain = Task {
    for await _ in stream {}
    if !Task.isCancelled { finished.setValue(true) }
  }
  defer { drain.cancel() }
  return await waitUntil(timeout: 2) { finished.value }
}
