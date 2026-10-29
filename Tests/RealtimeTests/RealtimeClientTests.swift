//
//  RealtimeClientTests.swift
//  Realtime
//
//  Created by Guilherme Souza on 23/10/26.
//

import ConcurrencyExtras
import Foundation
import Phoenix
import PhoenixTesting
import Testing

@testable import Realtime

@Suite(.timeLimit(.minutes(1)))
struct RealtimeClientTests {
  @Test
  func connectReturnsOnceOpenAndStatusNeedsNoAwait() async throws {
    let harness = RealtimeHarness()
    #expect(harness.client.status == .disconnected)

    let connection = try await harness.connect()

    #expect(harness.client.status == .connected)
    let query = URLComponents(url: connection.url, resolvingAgainstBaseURL: false)?.queryItems
    #expect(connection.url.path == "/realtime/v1/websocket")
    #expect(query?.contains(URLQueryItem(name: "apikey", value: "test-key")) == true)
    #expect(query?.contains(URLQueryItem(name: "vsn", value: "2.0.0")) == true)
  }

  @Test
  func connectWhenConnectedReturnsAtOnce() async throws {
    let harness = RealtimeHarness()
    try await harness.connect()

    try await harness.client.connect()

    #expect(harness.transport.connectionCount == 1)
  }

  @Test(arguments: [401, 403, 404])
  func refusedHandshakeStopsAfterOneAttempt(status: Int) async throws {
    let harness = RealtimeHarness()
    let statuses = harness.client.statusChange

    let connecting = Task { try await harness.client.connect() }
    let connection = await harness.transport.nextConnection()
    await connection.fail(httpStatus: status)

    let error = await #expect(throws: RealtimeError.self) { try await connecting.value }
    #expect(error?.kind == .transport)
    #expect(error?.isRetryable == false)
    #expect(harness.client.status == .disconnected)
    #expect(harness.transport.connectionCount == 1)
    #expect(await first(3, of: statuses) == [.disconnected, .connecting, .disconnected])
  }

  @Test
  func applicationCloseCodeStopsReconnecting() async throws {
    let harness = RealtimeHarness()
    let connection = try await harness.connect()
    let statuses = harness.client.statusChange

    await connection.serverClose(code: 4001, reason: "shutting down")

    _ = await collect(statuses) { $0.last == .disconnected }
    #expect(harness.client.status == .disconnected)
    #expect(harness.transport.connectionCount == 1)
  }

  @Test
  func droppedConnectionReconnectsAndRejoins() async throws {
    let harness = RealtimeHarness { $0.reconnectDelay = .seconds(1) }
    let connection = try await harness.connect()
    let channel = harness.client.channel("room")
    try await channel.subscribeWithError()
    let channelStatuses = channel.statusChange

    await connection.fail()
    #expect(harness.client.status == .connecting)
    await harness.advance(by: .seconds(1))
    let next = await harness.transport.nextConnection()
    await next.open()
    _ = await next.nextSent("phx_join")

    let seen = await collect(channelStatuses) { $0.last == .subscribed && $0.count > 1 }
    #expect(seen == [.subscribed, .subscribing, .subscribed])
    #expect(harness.client.status == .connected)
  }

  @Test
  func manyFailedAttemptsKeepReconnecting() async throws {
    let harness = RealtimeHarness {
      $0.reconnectDelay = .seconds(1)
      $0.maxRetryAttempts = 2
    }
    let connection = try await harness.connect()

    await connection.fail()
    for _ in 1...10 {
      await harness.advance(by: .seconds(30))
      let next = try #require(await harness.nextConnection())
      await next.fail()
      #expect(harness.client.status == .connecting)
    }
    await harness.advance(by: .seconds(30))
    let last = try #require(await harness.nextConnection())
    await last.open()

    #expect(harness.client.status == .connected)
    #expect(harness.transport.connectionCount == 12)
  }

  @Test
  func defaultOptionsReconnectWithinOneSecond() async throws {
    let harness = RealtimeHarness()
    let connection = try await harness.connect()

    await connection.fail()
    await harness.advance(by: .seconds(1))
    let next = try #require(await harness.nextConnection())
    await next.open()

    #expect(harness.client.status == .connected)
    #expect(harness.transport.connectionCount == 2)
  }

  @Test
  func connectDuringAReconnectTriesAtOnce() async throws {
    let harness = RealtimeHarness { $0.reconnectDelay = .seconds(30) }
    let connection = try await harness.connect()
    await connection.fail()
    await harness.socket.settle()
    #expect(harness.client.status == .connecting)
    #expect(harness.transport.connectionCount == 1)

    async let connected: Void = harness.client.connect()
    let next = try #require(await harness.nextConnection())
    await next.open()
    try await connected

    #expect(harness.client.status == .connected)
    #expect(harness.transport.connectionCount == 2)
  }

  @Test(arguments: [401, 403, 404])
  func refusedReconnectStops(status: Int) async throws {
    let harness = RealtimeHarness()
    let connection = try await harness.connect()

    await connection.fail()
    await harness.advance(by: .seconds(1))
    let next = try #require(await harness.nextConnection())
    await next.fail(httpStatus: status)
    await harness.advance(by: .seconds(60))

    #expect(harness.client.status == .disconnected)
    #expect(harness.transport.connectionCount == 2)
  }

  @Test
  func channelReturnsTheSameInstanceForATopic() {
    let harness = RealtimeHarness()

    let first = harness.client.channel("room")
    let second = harness.client.channel("room") { $0.isPrivate = true }

    #expect(first === second)
    #expect(first.topic == "realtime:room")
    #expect(!second.config.isPrivate)
    #expect(harness.client.channels.keys.sorted() == ["realtime:room"])
  }

  @Test
  func setAuthSendsTheTokenToSubscribedChannelsOnly() async throws {
    let harness = RealtimeHarness()
    let connection = try await harness.connect()
    let a = harness.client.channel("a")
    let b = harness.client.channel("b")
    _ = harness.client.channel("idle")
    try await a.subscribeWithError()
    try await b.subscribeWithError()
    _ = await connection.nextSent("phx_join")
    _ = await connection.nextSent("phx_join")

    await harness.client.setAuth("fresh-token")

    let first = await connection.nextSent("access_token")
    let second = await connection.nextSent("access_token")
    #expect(Set([first.topic, second.topic]) == ["realtime:a", "realtime:b"])
    #expect(first.payload.jsonObject["access_token"]?.stringValue == "fresh-token")

    let c = harness.client.channel("c")
    try await c.subscribeWithError()
    let join = await connection.nextSent("phx_join")
    #expect(join.payload.jsonObject["access_token"]?.stringValue == "fresh-token")
    #expect(connection.unreadSent.allSatisfy { $0.event != "access_token" })
  }

  @Test
  func setAuthWithTheSameTokenSendsNothing() async throws {
    let harness = RealtimeHarness()
    let connection = try await harness.connect()
    let channel = harness.client.channel("a")
    try await channel.subscribeWithError()
    await harness.client.setAuth("token")
    _ = await connection.nextSent("access_token")

    await harness.client.setAuth("token")
    await harness.socket.settle()

    #expect(connection.unreadSent.allSatisfy { $0.event != "access_token" })
  }

  @Test
  func removedChannelDoesNotRejoinAcrossAReconnect() async throws {
    let harness = RealtimeHarness { $0.reconnectDelay = .seconds(1) }
    let connection = try await harness.connect()
    let removed = harness.client.channel("removed")
    let kept = harness.client.channel("kept")
    try await removed.subscribeWithError()
    try await kept.subscribeWithError()
    let keptStatuses = kept.statusChange

    await connection.fail()
    #expect(harness.client.status == .connecting)
    await harness.client.removeChannel(removed)
    let removedStatuses = removed.statusChange
    await harness.advance(by: .seconds(1))
    let next = await harness.transport.nextConnection()
    await next.open()

    let rejoin = await next.nextSent("phx_join")
    #expect(rejoin.topic == "realtime:kept")
    _ = await collect(keptStatuses) { $0.suffix(2) == [.subscribing, .subscribed] }
    #expect(await first(2, of: removedStatuses) == [.unsubscribed])
    #expect(removed.status == .unsubscribed)
    #expect(harness.client.channels.keys.sorted() == ["realtime:kept"])
    #expect(next.unreadSent.allSatisfy { $0.topic != "realtime:removed" })
    let error = await #expect(throws: RealtimeError.self) { try await removed.subscribeWithError() }
    #expect(error?.kind == .channelClosed)
    #expect(error?.isRetryable == false)
  }

  @Test
  func removingTheLastChannelDisconnectsAfterTheDelay() async throws {
    let harness = RealtimeHarness { $0.disconnectOnEmptyChannelsAfter = .seconds(5) }
    try await harness.connect()
    let channel = harness.client.channel("room")
    try await channel.subscribeWithError()
    let statuses = harness.client.statusChange

    let sleepers = harness.clock.sleeperCount
    await harness.client.removeChannel(channel)
    #expect(harness.client.status == .connected)
    await harness.clock.waitForSleepers(sleepers + 1)
    harness.clock.advance(by: .seconds(5))

    _ = await collect(statuses) { $0.last == .disconnected }
    #expect(harness.client.channels.isEmpty)
  }

  @Test
  func disconnectKeepsMembershipAndConnectRejoins() async throws {
    let harness = RealtimeHarness()
    try await harness.connect()
    let channel = harness.client.channel("room")
    try await channel.subscribeWithError()

    await harness.client.disconnect()
    #expect(harness.client.status == .disconnected)
    #expect(channel.status == .subscribing)

    let statuses = channel.statusChange
    let connection = try await harness.connect()
    _ = await connection.nextSent("phx_join")
    _ = await collect(statuses) { $0.last == .subscribed }
    #expect(channel.status == .subscribed)
  }

  @Test
  func heartbeatMapsTheSocketHeartbeats() async throws {
    let harness = RealtimeHarness { $0.heartbeatInterval = .seconds(5) }
    try await harness.connect()
    let heartbeats = harness.client.heartbeat

    await harness.advance(by: .seconds(5))

    #expect(await first(2, of: heartbeats) == [.sent, .ok])
  }

  @Test
  func channelDuringARemovalReturnsANewChannel() async throws {
    let harness = RealtimeHarness(
      replies: ServerReplies { frame in frame.event == "phx_join" ? .ok() : nil })
    let connection = try await harness.connect()
    let old = harness.client.channel("room")
    try await old.subscribeWithError()

    let removing = Task { await harness.client.removeChannel(old) }
    _ = await connection.nextSent("phx_leave")
    let fresh = harness.client.channel("room")
    try await fresh.subscribeWithError()
    await harness.advance(by: RealtimeClientOptions.defaultTimeout)
    await removing.value

    #expect(fresh !== old)
    #expect(fresh.status == .subscribed)
    #expect(harness.client.channels["realtime:room"] === fresh)
  }

  @Test
  func aTokenThatAJoinFetchedReachesTheOtherChannels() async throws {
    let provided = LockIsolated("t1")
    let harness = RealtimeHarness { $0.accessToken = { provided.value } }
    let connection = try await harness.connect()
    let a = harness.client.channel("a")
    try await a.subscribeWithError()
    provided.setValue("t2")

    let b = harness.client.channel("b")
    try await b.subscribeWithError()

    let frames = await collect(connection) { frames in
      frames.filter { $0.event == "phx_join" }.count == 2
        && frames.contains { $0.event == "access_token" }
    }
    #expect(frames.last { $0.event == "phx_join" }?.accessToken == "t2")
    let pushes = frames.filter { $0.event == "access_token" }
    #expect(pushes.map(\.topic) == ["realtime:a"])
    #expect(pushes.first?.accessToken == "t2")
    await harness.client.setAuth("t2")
    await harness.socket.settle()
    #expect(connection.unreadSent.allSatisfy { $0.event != "access_token" })
  }

  @Test
  func aTokenSentDuringAJoinThatFailsDoesNotOutliveTheRejoin() async throws {
    let harness = RealtimeHarness(replies: .realtime(join: { _ in nil })) {
      $0.headers[.authorization] = "Bearer user-1"
      $0.reconnectDelay = .seconds(1)
    }
    let connection = try await harness.connect()
    let channel = harness.client.channel("room")
    let subscribing = Task { try await channel.subscribeWithError() }
    _ = await connection.nextSent("phx_join")

    await harness.client.setAuth("user-2")
    await connection.fail()
    await harness.client.setAuth("anon")
    await harness.advance(by: .seconds(1))
    let next = try #require(await harness.nextConnection())
    await next.open()
    let rejoin = await next.nextSent("phx_join")
    await next.reply(to: rejoin)
    try await subscribing.value
    await harness.client.setAuth("anon")
    await harness.socket.settle()

    #expect(rejoin.accessToken == "anon")
    let tokens = next.unreadSent.filter { $0.event == "access_token" }.map(\.accessToken)
    #expect(!tokens.contains("user-2"))
    #expect(tokens.last ?? "anon" == "anon")
  }

  @Test
  func aCallbackThatIgnoresItsTimeoutIsNotCalledAgainUntilItReturns() async throws {
    let callback = TokenCallback("t1")
    let harness = RealtimeHarness { $0.accessToken = callback.closure }
    try await harness.connect()
    await harness.advance(by: .seconds(10))
    callback.hold()
    let refreshing = Task { await harness.client.setAuth() }
    await callback.nextHeldCall()
    await harness.advance(by: RealtimeClientOptions.defaultTimeout / 2)
    await refreshing.value
    let calls = callback.calls

    await harness.advance(by: .seconds(10))
    await harness.client.setAuth()
    #expect(callback.calls == calls)

    callback.set("t2")
    callback.release(returning: "late")
    await harness.advance(by: .seconds(10))
    let client = harness.client
    let calledAgain = await within(.seconds(5)) {
      while callback.calls == calls {
        await client.setAuth()
        try? await Task.sleep(for: .milliseconds(1))
      }
    }
    #expect(calledAgain != nil)
    #expect(callback.calls == calls + 1)
    #expect(harness.client.connection.tokens.token == "t2")
  }

  @Test
  func aSubscribeRightAfterSignInAsksTheCallbackInsideTheThrottleWindow() async throws {
    let callback = TokenCallback("anon")
    let harness = RealtimeHarness { $0.accessToken = callback.closure }
    let connection = try await harness.connect()
    callback.set("user")

    try await harness.client.channel("room").subscribeWithError()

    let join = await connection.nextSent("phx_join")
    #expect(join.accessToken == "user")
  }

  @Test
  func theFirstSubscribeOnANewSocketAsksTheCallbackOnce() async throws {
    let callback = TokenCallback("t1")
    let harness = RealtimeHarness { $0.accessToken = callback.closure }
    let channel = harness.client.channel("room")

    async let subscribed: Void = channel.subscribeWithError()
    let connection = await harness.transport.nextConnection()
    await connection.open()
    try await subscribed

    #expect(callback.calls == 1)
  }

  @Test
  func eachHeartbeatSendsTheProvidersNewTokenToChannels() async throws {
    let provided = LockIsolated("t1")
    let harness = RealtimeHarness {
      $0.accessToken = { provided.value }
      $0.heartbeatInterval = .seconds(10)
    }
    let connection = try await harness.connect()
    let channel = harness.client.channel("room")
    try await channel.subscribeWithError()
    provided.setValue("t2")

    await harness.advance(by: .seconds(10))

    let pushed = await connection.nextSent("access_token")
    #expect(pushed.payload.jsonObject["access_token"]?.stringValue == "t2")
  }

  @Test
  func rejoinAfterAReconnectSendsTheProvidersNewToken() async throws {
    let provided = LockIsolated("t1")
    let harness = RealtimeHarness {
      $0.accessToken = { provided.value }
      $0.reconnectDelay = .seconds(1)
    }
    let connection = try await harness.connect()
    let channel = harness.client.channel("room")
    try await channel.subscribeWithError()
    provided.setValue("t2")
    await harness.advance(by: TokenBox.refreshInterval)

    await connection.fail()
    await harness.advance(by: .seconds(1))
    let next = await harness.transport.nextConnection()
    await next.open()

    let rejoin = await next.nextSent("phx_join")
    #expect(rejoin.payload.jsonObject["access_token"]?.stringValue == "t2")
  }

  @Test
  func socketLogsCarryNoURLQuery() async throws {
    let text = "connecting to wss://x.supabase.co/realtime/v1/websocket?apikey=secret&vsn=2.0.0 now"

    let redacted = redactingURLQueries(text)

    #expect(redacted == "connecting to wss://x.supabase.co/realtime/v1/websocket?<redacted> now")
  }
}
