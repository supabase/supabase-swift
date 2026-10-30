//
//  RealtimeCoreSubscribeTests.swift
//  RealtimeTests
//

import Foundation
import Helpers
import TestHelpers
import Testing

@testable import Realtime

/// The subscribe, join, and rejoin transitions of ``RealtimeCore``: which frames and timers a
/// `subscribe` starts, and how join replies, join timeouts, and rejoin timers move the channel on.
@Suite
struct RealtimeCoreSubscribeTests {
  typealias Event = RealtimeCore.Event
  typealias Effect = RealtimeCore.Effect

  static let topic = "room"
  static let noStreams = JoinSnapshot(bindings: [], presenceEnabled: false)
  static let transient = RealtimeError.joinError(reason: "UnknownErrorOnChannel: boom")
  static let rateLimited = RealtimeError.joinError(
    reason: "ClientJoinRateLimitReached: Too many joins per second")
  static let denied = RealtimeError.joinError(
    reason: "Unauthorized: You do not have permissions to read from this Channel topic: room")

  @Test
  func subscribeWhileConnectedSendsJoin() throws {
    var options = RealtimeCore.Options.test
    options.version = "realtime-swift/test"
    var harness = CoreHarness.connected(options: options, initialToken: "token")
    var configuration = RealtimeChannelConfiguration()
    configuration.isPrivate = true
    configuration.presence.key = "me"
    let snapshot = JoinSnapshot(
      bindings: [PostgresJoinConfig(event: .insert, schema: "public", table: "messages")],
      presenceEnabled: true)
    let w = harness.waiter()

    let effects = harness.send(
      .subscribe(
        channel: .room, topic: Self.topic, configuration: configuration, waiter: w,
        snapshot: snapshot))

    let payload = RealtimeJoinPayload(
      config: RealtimeJoinConfig(
        configuration, bindings: snapshot.bindings, presenceEnabled: snapshot.presenceEnabled),
      accessToken: "token",
      version: "realtime-swift/test")
    #expect(
      effects == [
        .publishChannelStatus(.room, .subscribing(attempt: 1)),
        .send(try Self.join(ref: "1", payload: payload)),
        .schedule(.joinTimeout(channel: .room, ref: "1"), after: .seconds(10)),
      ])
    #expect(
      harness.core.channels[.room]?.phase == .joining(ref: "1", attempt: 1, stage: .reply))
    #expect(harness.core.channels[.room]?.joinAccessToken == "token")
  }

  @Test
  func joinTimeoutIncludesTheServerPostgresWait() throws {
    var harness = CoreHarness.connected()
    var configuration = RealtimeChannelConfiguration()
    configuration.postgresChanges.waitForSubscription = true
    configuration.postgresChanges.subscriptionTimeout = .seconds(15)
    let snapshot = JoinSnapshot(
      bindings: [PostgresJoinConfig(event: .all, schema: "public")], presenceEnabled: false)

    let effects = harness.send(
      .subscribe(
        channel: .room, topic: Self.topic, configuration: configuration, waiter: harness.waiter(),
        snapshot: snapshot))

    #expect(
      effects.last == .schedule(.joinTimeout(channel: .room, ref: "1"), after: .seconds(25)))
  }

  @Test
  func joinOkResolvesAllWaiters() throws {
    var harness = CoreHarness.connected()
    let w1 = harness.waiter()
    let w2 = harness.waiter()

    _ = harness.send(Self.subscribe(w1))
    #expect(harness.send(Self.subscribe(w2)) == [])

    #expect(
      harness.send(.frame(Self.reply(ref: "1"))) == [
        .resume(w1, .success),
        .resume(w2, .success),
        .publishChannelStatus(.room, .subscribed),
        .cancel(.joinTimeout(channel: .room, ref: "1")),
      ])
    #expect(harness.core.channels[.room]?.phase == .subscribed(joinRef: "1"))
    #expect(harness.core.channels[.room]?.subscribeWaiters == [])
  }

  @Test
  func subscribeOnSubscribedResolvesAtOnce() {
    var harness = Self.subscribed()
    let w = harness.waiter()

    #expect(harness.send(Self.subscribe(w)) == [.resume(w, .success)])
  }

  @Test
  func retryableJoinErrorWaitsAndRejoins() throws {
    var harness = CoreHarness.connected()
    _ = harness.send(Self.subscribe(harness.waiter()))

    #expect(
      harness.send(.frame(Self.reply(ref: "1", error: Self.transient))) == [
        .publishChannelStatus(
          .room,
          .resubscribing(attempt: 1, retryIn: .seconds(1), lastError: Self.transient)),
        .schedule(.rejoin(channel: .room), after: .seconds(1)),
        .cancel(.joinTimeout(channel: .room, ref: "1")),
      ])

    #expect(
      harness.send(.timerFired(.rejoin(channel: .room))) == [
        .publishChannelStatus(.room, .subscribing(attempt: 2)),
        .send(try Self.join(ref: "2")),
        .schedule(.joinTimeout(channel: .room, ref: "2"), after: .seconds(10)),
      ])
  }

  @Test
  func eachRejoinWaitsForItsAttempt() {
    var harness = CoreHarness.connected()
    _ = harness.send(Self.subscribe(harness.waiter()))
    _ = harness.send(.frame(Self.reply(ref: "1", error: Self.transient)))
    _ = harness.send(.timerFired(.rejoin(channel: .room)))

    let effects = harness.send(.frame(Self.reply(ref: "2", error: Self.transient)))

    #expect(effects.contains(.schedule(.rejoin(channel: .room), after: .seconds(2))))
    #expect(
      harness.core.channels[.room]?.phase
        == .waitingToRetry(attempt: 2, retryIn: .seconds(2), lastError: Self.transient))
  }

  @Test
  func rateLimitedWaitsThirtySeconds() {
    var harness = CoreHarness.connected()
    _ = harness.send(Self.subscribe(harness.waiter()))

    #expect(
      harness.send(.frame(Self.reply(ref: "1", error: Self.rateLimited))) == [
        .publishChannelStatus(
          .room,
          .resubscribing(attempt: 1, retryIn: .seconds(30), lastError: Self.rateLimited)),
        .schedule(.rejoin(channel: .room), after: .seconds(30)),
        .cancel(.joinTimeout(channel: .room, ref: "1")),
      ])
  }

  @Test
  func fatalJoinErrorFailsWaiters() {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w))

    #expect(
      harness.send(.frame(Self.reply(ref: "1", error: Self.denied))) == [
        .resume(w, .failure(Self.denied)),
        .publishChannelStatus(.room, .failed(Self.denied)),
        .cancel(.joinTimeout(channel: .room, ref: "1")),
      ])
    #expect(harness.core.channels[.room]?.phase == .failed(Self.denied))
    #expect(harness.core.channels[.room]?.subscribeWaiters == [])
  }

  @Test
  func subscribeAfterFailureStartsOver() throws {
    var harness = CoreHarness.connected()
    _ = harness.send(Self.subscribe(harness.waiter()))
    _ = harness.send(.frame(Self.reply(ref: "1", error: Self.denied)))

    #expect(
      harness.send(Self.subscribe(harness.waiter())) == [
        .publishChannelStatus(.room, .subscribing(attempt: 1)),
        .send(try Self.join(ref: "2")),
        .schedule(.joinTimeout(channel: .room, ref: "2"), after: .seconds(10)),
      ])
  }

  @Test
  func joinTimeoutRetries() {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w))

    #expect(
      harness.send(.timerFired(.joinTimeout(channel: .room, ref: "1"))) == [
        .publishChannelStatus(
          .room,
          .resubscribing(attempt: 1, retryIn: .seconds(1), lastError: .joinTimeout)),
        .schedule(.rejoin(channel: .room), after: .seconds(1)),
      ])
    #expect(harness.core.channels[.room]?.subscribeWaiters == [w])
  }

  @Test
  func lateOkAfterTimeoutConfirms() {
    var harness = CoreHarness.connected()
    let w1 = harness.waiter()
    let w2 = harness.waiter()
    _ = harness.send(Self.subscribe(w1))
    _ = harness.send(.timerFired(.joinTimeout(channel: .room, ref: "1")))
    _ = harness.send(Self.subscribe(w2))

    #expect(
      harness.send(.frame(Self.reply(ref: "1"))) == [
        .resume(w1, .success),
        .resume(w2, .success),
        .publishChannelStatus(.room, .subscribed),
        .cancel(.rejoin(channel: .room)),
      ])
    #expect(harness.core.channels[.room]?.phase == .subscribed(joinRef: "1"))
    #expect(harness.send(.timerFired(.rejoin(channel: .room))) == [])
  }

  @Test
  func okForOlderRefStillIgnored() {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w))
    _ = harness.send(.timerFired(.joinTimeout(channel: .room, ref: "1")))
    _ = harness.send(.timerFired(.rejoin(channel: .room)))
    _ = harness.send(.timerFired(.joinTimeout(channel: .room, ref: "2")))

    #expect(harness.send(.frame(Self.reply(ref: "1"))) == [])
    #expect(
      harness.core.channels[.room]?.phase
        == .waitingToRetry(attempt: 2, retryIn: .seconds(2), lastError: .joinTimeout))

    _ = harness.send(.timerFired(.rejoin(channel: .room)))
    #expect(harness.send(.timerFired(.joinTimeout(channel: .room, ref: "2"))) == [])
    #expect(harness.send(.frame(Self.reply(ref: "2"))) == [])
    #expect(
      harness.send(.frame(Self.reply(ref: "3"))) == [
        .resume(w, .success),
        .publishChannelStatus(.room, .subscribed),
        .cancel(.joinTimeout(channel: .room, ref: "3")),
      ])
  }

  @Test
  func lateOkAfterJoinErrorIsIgnored() {
    var harness = CoreHarness.connected()
    _ = harness.send(Self.subscribe(harness.waiter()))
    _ = harness.send(.frame(Self.reply(ref: "1", error: Self.transient)))

    #expect(harness.send(.frame(Self.reply(ref: "1"))) == [])
  }

  @Test
  func rejoinTimerIsIgnoredUnlessWaitingToRetry() {
    var harness = Self.subscribed()

    #expect(harness.send(.timerFired(.rejoin(channel: .room))) == [])
    #expect(harness.send(.timerFired(.rejoin(channel: .other))) == [])
  }

  @Test
  func subscribeWhileDisconnectedConnectsFirst() throws {
    var harness = CoreHarness()
    let socket = FakeWebSocket.fakes().0
    let w = harness.waiter()

    #expect(
      harness.send(Self.subscribe(w)) == [
        .publishChannelStatus(.room, .subscribing(attempt: 1)),
        .publishClientStatus(.connecting(attempt: 1)),
        .openSocket,
      ])
    #expect(harness.core.channels[.room]?.phase == .waitingForSocket(attempt: 1))

    #expect(
      harness.send(.socketOpened(socket)) == [
        .publishClientStatus(.connected),
        .installSocket(socket),
        .schedule(.heartbeat, after: .seconds(25)),
        .send(try Self.join(ref: "1")),
        .schedule(.joinTimeout(channel: .room, ref: "1"), after: .seconds(10)),
      ])
    #expect(
      harness.core.channels[.room]?.phase == .joining(ref: "1", attempt: 1, stage: .reply))
  }

  @Test
  func subscribeWhileConnectingWaitsForTheSocket() {
    var harness = CoreHarness()
    _ = harness.send(.connect(waiter: nil))

    #expect(
      harness.send(Self.subscribe(harness.waiter())) == [
        .publishChannelStatus(.room, .subscribing(attempt: 1))
      ])
    #expect(harness.core.channels[.room]?.phase == .waitingForSocket(attempt: 1))
  }

  @Test
  func subscribeWhileDisconnectedWithoutConnectOnSubscribeFails() {
    var options = RealtimeCore.Options.test
    options.connectOnSubscribe = false
    var harness = CoreHarness(options: options)
    let w = harness.waiter()

    #expect(
      harness.send(Self.subscribe(w)) == [
        .resume(w, .failure(.notConnectedToSubscribe)),
        .publishChannelStatus(.room, .failed(.notConnectedToSubscribe)),
      ])
  }

  @Test
  func refusedConnectFailsTheWaitingSubscribe() {
    var harness = CoreHarness()
    let w = harness.waiter()
    let refused = RealtimeError.upgradeFailed(status: 401)
    _ = harness.send(Self.subscribe(w))

    #expect(
      harness.send(.socketOpenFailed(refused)) == [
        .publishClientStatus(.disconnected(refused)),
        .resume(w, .failure(refused)),
        .publishChannelStatus(.room, .failed(refused)),
      ])
  }

  @Test
  func transientConnectFailureWaitsAndConnectsAgain() {
    var harness = CoreHarness()
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w))

    #expect(
      harness.send(.socketOpenFailed(.transport("unreachable"))) == [
        .publishClientStatus(.disconnected(.transport("unreachable"))),
        .publishChannelStatus(
          .room,
          .resubscribing(attempt: 1, retryIn: .seconds(1), lastError: .notConnected)),
        .schedule(.rejoin(channel: .room), after: .seconds(1)),
      ])

    #expect(
      harness.send(.timerFired(.rejoin(channel: .room))) == [
        .publishChannelStatus(.room, .subscribing(attempt: 2)),
        .publishClientStatus(.connecting(attempt: 1)),
        .openSocket,
      ])
    #expect(harness.core.channels[.room]?.subscribeWaiters == [w])
  }

  @Test
  func resubscribedEventOnRejoinAfterFirstSuccess() {
    var harness = Self.subscribed()
    let w = harness.waiter()
    _ = harness.send(.socketClosed(code: 1001, reason: nil))
    _ = harness.send(Self.subscribe(w))
    _ = harness.send(.timerFired(.reconnect))
    _ = harness.send(.socketOpened(FakeWebSocket.fakes().0))

    #expect(
      harness.send(.frame(Self.reply(ref: "2"))) == [
        .resume(w, .success),
        .publishChannelStatus(.room, .subscribed),
        .deliver(.room, .event(.resubscribed)),
        .cancel(.joinTimeout(channel: .room, ref: "2")),
      ])
  }

  @Test
  func firstSubscribeCancelsIdleDisconnect() throws {
    var harness = CoreHarness.connected()
    _ = harness.send(.lastChannelRemoved(disconnectAfter: .seconds(50)))

    #expect(
      harness.send(Self.subscribe(harness.waiter())) == [
        .cancel(.idleDisconnect),
        .publishChannelStatus(.room, .subscribing(attempt: 1)),
        .send(try Self.join(ref: "1")),
        .schedule(.joinTimeout(channel: .room, ref: "1"), after: .seconds(10)),
      ])
    #expect(
      harness.send(
        .subscribe(
          channel: .other, topic: "other", configuration: RealtimeChannelConfiguration(),
          waiter: harness.waiter(), snapshot: Self.noStreams)
      ).first == .publishChannelStatus(.other, .subscribing(attempt: 1)))
  }

  // MARK: Helpers

  static func subscribe(
    _ waiter: WaiterID, channel: ChannelID = .room, snapshot: JoinSnapshot = noStreams
  ) -> Event {
    .subscribe(
      channel: channel, topic: topic, configuration: RealtimeChannelConfiguration(), waiter: waiter,
      snapshot: snapshot)
  }

  /// A connected harness whose channel joined with ref `"1"`. It used waiter id 1.
  static func subscribed() -> CoreHarness {
    var harness = CoreHarness.connected()
    let room = harness.channel()
    _ = harness.send(subscribe(harness.waiter(), channel: room))
    _ = harness.send(.frame(reply(ref: "1")))
    return harness
  }

  static func join(ref: Ref, payload: RealtimeJoinPayload? = nil) throws -> RealtimeMessage {
    let payload =
      payload
      ?? RealtimeJoinPayload(
        config: RealtimeJoinConfig(
          RealtimeChannelConfiguration(), bindings: [], presenceEnabled: false),
        accessToken: nil, version: nil)
    return RealtimeMessage(
      joinRef: ref, ref: ref, topic: "realtime:\(topic)", event: "phx_join",
      payload: try JSONObject(payload))
  }

  static func reply(ref: Ref, error: RealtimeError? = nil) -> RealtimeMessage {
    let payload: JSONObject =
      if let error {
        ["status": "error", "response": ["reason": .string(error.message)]]
      } else {
        ["status": "ok", "response": [:]]
      }
    return RealtimeMessage(
      joinRef: ref, ref: ref, topic: "realtime:\(topic)", event: "phx_reply", payload: payload)
  }
}
