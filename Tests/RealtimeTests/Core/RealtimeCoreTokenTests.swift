//
//  RealtimeCoreTokenTests.swift
//  RealtimeTests
//

import Foundation
import Helpers
import TestHelpers
import Testing

@testable import Realtime

/// The access token in ``RealtimeCore``: the fetch before a join, the fresh-token rejoin after an
/// expired token, `setAuth`, the refresh timer, and the token sent to joined channels.
@Suite
struct RealtimeCoreTokenTests {
  typealias Event = RealtimeCore.Event
  typealias Effect = RealtimeCore.Effect

  static let topic = "room"
  static let expired = RealtimeError.joinError(
    reason: "InvalidJWTToken: Token has expired 3 seconds ago")
  static let transient = RealtimeError.joinError(reason: "UnknownErrorOnChannel: boom")

  /// ``RealtimeCore/Options/test`` with an `accessToken` callback.
  static var withProvider: RealtimeCore.Options {
    var options = RealtimeCore.Options.test
    options.hasAccessTokenProvider = true
    return options
  }

  // MARK: The fetch before a join

  @Test
  func joinFetchesTokenFirstWhenProviderSet() throws {
    var harness = CoreHarness.connected(options: Self.withProvider)

    #expect(
      harness.send(Self.subscribe(harness.waiter())) == [
        .publishChannelStatus(.room, .subscribing(attempt: 1)),
        .fetchAccessToken(generation: 1),
      ])
    #expect(harness.core.channels[.room]?.phase == .refreshingToken(attempt: 1))

    #expect(
      harness.send(.tokenFetched(token: "t1", generation: 1)) == [
        .send(try Self.join(ref: "1", token: "t1")),
        .schedule(.joinTimeout(channel: .room, ref: "1"), after: .seconds(10)),
      ])
    #expect(
      harness.core.channels[.room]?.phase == .joining(ref: "1", attempt: 1, stage: .reply))
    #expect(harness.core.channels[.room]?.joinAccessToken == "t1")
  }

  @Test
  func joinWithoutProviderSkipsTheFetch() throws {
    var harness = CoreHarness.connected(initialToken: "t0")

    #expect(
      harness.send(Self.subscribe(harness.waiter())) == [
        .publishChannelStatus(.room, .subscribing(attempt: 1)),
        .send(try Self.join(ref: "1", token: "t0")),
        .schedule(.joinTimeout(channel: .room, ref: "1"), after: .seconds(10)),
      ])
  }

  @Test
  func joinSkipsFetchWithinRefreshInterval() throws {
    var harness = CoreHarness.connected(options: Self.withProvider)
    let a = harness.channel()
    let b = harness.channel()
    let c = harness.channel()
    _ = harness.send(Self.subscribe(harness.waiter(), channel: a, topic: "a"))
    _ = harness.send(.tokenFetched(token: "t1", generation: 1))

    harness.advance(by: .seconds(9))
    #expect(
      harness.send(Self.subscribe(harness.waiter(), channel: b, topic: "b")) == [
        .publishChannelStatus(b, .subscribing(attempt: 1)),
        .send(try Self.join(ref: "2", token: "t1", topic: "b")),
        .schedule(.joinTimeout(channel: b, ref: "2"), after: .seconds(10)),
      ])

    harness.advance(by: .seconds(1))
    #expect(
      harness.send(Self.subscribe(harness.waiter(), channel: c, topic: "c")) == [
        .publishChannelStatus(c, .subscribing(attempt: 1)),
        .fetchAccessToken(generation: 2),
      ])
  }

  /// Review Focus 4: a callback that throws or returns `nil` keeps the stored token, and the
  /// joins waiting for it go ahead with that token.
  @Test
  func joinsProceedWithStoredTokenWhenFetchReturnsNil() throws {
    var harness = CoreHarness.connected(options: Self.withProvider, initialToken: "t0")
    _ = harness.send(Self.subscribe(harness.waiter()))

    #expect(
      harness.send(.tokenFetched(token: nil, generation: 1)) == [
        .send(try Self.join(ref: "1", token: "t0")),
        .schedule(.joinTimeout(channel: .room, ref: "1"), after: .seconds(10)),
      ])
    #expect(harness.core.tokens.token == "t0")
  }

  @Test
  func twoJoinsShareOneFetch() throws {
    var harness = CoreHarness.connected(options: Self.withProvider)
    let a = harness.channel()
    let b = harness.channel()

    #expect(
      harness.send(Self.subscribe(harness.waiter(), channel: a, topic: "a")) == [
        .publishChannelStatus(a, .subscribing(attempt: 1)),
        .fetchAccessToken(generation: 1),
      ])
    #expect(
      harness.send(Self.subscribe(harness.waiter(), channel: b, topic: "b")) == [
        .publishChannelStatus(b, .subscribing(attempt: 1))
      ])
    #expect(harness.core.channels[b]?.phase == .refreshingToken(attempt: 1))

    #expect(
      harness.send(.tokenFetched(token: "t1", generation: 1)) == [
        .send(try Self.join(ref: "1", token: "t1", topic: "a")),
        .schedule(.joinTimeout(channel: a, ref: "1"), after: .seconds(10)),
        .send(try Self.join(ref: "2", token: "t1", topic: "b")),
        .schedule(.joinTimeout(channel: b, ref: "2"), after: .seconds(10)),
      ])
  }

  // MARK: Expired token

  @Test
  func expiredTokenRefreshesOnceThenRejoins() throws {
    var harness = CoreHarness.connected(options: Self.withProvider)
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w))
    _ = harness.send(.tokenFetched(token: "t1", generation: 1))

    // Inside the refresh interval: the refused token must be replaced anyway.
    #expect(
      harness.send(.frame(Self.reply(ref: "1", error: Self.expired))) == [
        .publishChannelStatus(.room, .subscribing(attempt: 2)),
        .fetchAccessToken(generation: 2),
        .cancel(.joinTimeout(channel: .room, ref: "1")),
      ])
    #expect(harness.core.channels[.room]?.phase == .refreshingToken(attempt: 2))

    #expect(
      harness.send(.tokenFetched(token: "t2", generation: 2)) == [
        .send(try Self.join(ref: "2", token: "t2")),
        .schedule(.joinTimeout(channel: .room, ref: "2"), after: .seconds(10)),
      ])
    #expect(
      harness.core.channels[.room]?.phase == .joining(ref: "2", attempt: 2, stage: .reply))

    #expect(
      harness.send(.frame(Self.reply(ref: "2", error: Self.expired))) == [
        .resume(w, .failure(Self.expired)),
        .publishChannelStatus(.room, .failed(Self.expired)),
        .cancel(.joinTimeout(channel: .room, ref: "2")),
      ])
    #expect(harness.core.channels[.room]?.phase == .failed(Self.expired))
  }

  /// The one fresh-token rejoin is per run of expired-token errors: a token that expires again
  /// after another failure gets another one.
  @Test
  func tokenThatExpiresAgainAfterAnotherFailureIsRefreshedAgain() throws {
    var harness = CoreHarness.connected(options: Self.withProvider)
    _ = harness.send(Self.subscribe(harness.waiter()))
    _ = harness.send(.tokenFetched(token: "t1", generation: 1))
    _ = harness.send(.frame(Self.reply(ref: "1", error: Self.expired)))
    _ = harness.send(.tokenFetched(token: "t2", generation: 2))
    _ = harness.send(.frame(Self.reply(ref: "2", error: Self.transient)))
    _ = harness.send(.timerFired(.rejoin(channel: .room)))

    #expect(
      harness.send(.frame(Self.reply(ref: "3", error: Self.expired))) == [
        .publishChannelStatus(.room, .subscribing(attempt: 4)),
        .fetchAccessToken(generation: 3),
        .cancel(.joinTimeout(channel: .room, ref: "3")),
      ])
  }

  /// A fetch in flight started before the refusal and may return the refused token, so the
  /// channel waits for a fetch that starts after it.
  @Test
  func expiredTokenDuringAFetchWaitsForTheNextFetch() throws {
    var harness = CoreHarness.connected(options: Self.withProvider)
    _ = harness.send(Self.subscribe(harness.waiter()))
    _ = harness.send(.tokenFetched(token: "t1", generation: 1))
    harness.advance(by: .seconds(10))
    #expect(harness.send(.setAuth(token: nil)) == [.fetchAccessToken(generation: 2)])

    #expect(
      harness.send(.frame(Self.reply(ref: "1", error: Self.expired))) == [
        .publishChannelStatus(.room, .subscribing(attempt: 2)),
        .cancel(.joinTimeout(channel: .room, ref: "1")),
      ])
    #expect(
      harness.send(.tokenFetched(token: "t1", generation: 2)) == [.fetchAccessToken(generation: 3)])
    #expect(harness.core.channels[.room]?.phase == .refreshingToken(attempt: 2))

    #expect(
      harness.send(.tokenFetched(token: "t3", generation: 3)) == [
        .send(try Self.join(ref: "2", token: "t3")),
        .schedule(.joinTimeout(channel: .room, ref: "2"), after: .seconds(10)),
      ])
  }

  // MARK: setAuth and the token sent to channels

  /// Port of `pushAccessToken`: a subscribed channel gets the new token, and so does a join in
  /// flight that went out with another token.
  @Test
  func newTokenIsPushedToSubscribedAndJoiningChannels() throws {
    var harness = CoreHarness.connected(options: Self.withProvider, initialToken: "t0")
    let a = harness.channel()
    let b = harness.channel()
    let c = harness.channel()
    _ = harness.send(Self.subscribe(harness.waiter(), channel: a, topic: "a"))
    _ = harness.send(.tokenFetched(token: nil, generation: 1))
    _ = harness.send(.frame(Self.reply(ref: "1", topic: "a")))
    harness.advance(by: .seconds(5))
    _ = harness.send(Self.subscribe(harness.waiter(), channel: b, topic: "b"))
    harness.advance(by: .seconds(5))
    _ = harness.send(Self.subscribe(harness.waiter(), channel: c, topic: "c"))
    #expect(harness.core.channels[b]?.joinAccessToken == "t0")

    #expect(
      harness.send(.tokenFetched(token: "t1", generation: 2)) == [
        .send(try Self.join(ref: "3", token: "t1", topic: "c")),
        .schedule(.joinTimeout(channel: c, ref: "3"), after: .seconds(10)),
        .send(Self.accessToken("t1", joinRef: "1", ref: "4", topic: "a")),
        .send(Self.accessToken("t1", joinRef: "2", ref: "5", topic: "b")),
      ])
  }

  @Test
  func setAuthStoresAndPushesTheToken() {
    var harness = CoreHarness.connected(initialToken: "t0")
    _ = harness.send(Self.subscribe(harness.waiter()))
    _ = harness.send(.frame(Self.reply(ref: "1")))

    #expect(
      harness.send(.setAuth(token: "t1")) == [.send(Self.accessToken("t1", joinRef: "1", ref: "2"))]
    )
    #expect(harness.core.tokens.token == "t1")
    #expect(harness.send(.setAuth(token: "t1")) == [])
    // No callback: `setAuth()` has nothing to fetch from.
    #expect(harness.send(.setAuth(token: nil)) == [])
  }

  @Test
  func staleFetchResultIsDropped() throws {
    var harness = CoreHarness.connected(options: Self.withProvider)
    _ = harness.send(Self.subscribe(harness.waiter()))

    #expect(harness.send(.setAuth(token: "t2")) == [])
    // The waiting join goes ahead with the newer token.
    #expect(
      harness.send(.tokenFetched(token: "t1", generation: 1)) == [
        .send(try Self.join(ref: "1", token: "t2")),
        .schedule(.joinTimeout(channel: .room, ref: "1"), after: .seconds(10)),
      ])
    #expect(harness.core.tokens.token == "t2")
    #expect(harness.core.tokenFetchInFlight == false)
    // The fetch is over: the next one may start.
    harness.advance(by: .seconds(10))
    #expect(harness.send(.setAuth(token: nil)) == [.fetchAccessToken(generation: 3)])
  }

  /// Each fetch has its own generation: a late or duplicate result for an earlier fetch does not
  /// end the fetch in flight.
  @Test
  func duplicateFetchResultWhileANewerFetchRunsIsIgnored() throws {
    var harness = CoreHarness.connected(options: Self.withProvider)
    let a = harness.channel()
    let b = harness.channel()
    _ = harness.send(Self.subscribe(harness.waiter(), channel: a, topic: "a"))
    _ = harness.send(.tokenFetched(token: "t1", generation: 1))
    harness.advance(by: .seconds(10))
    #expect(
      harness.send(Self.subscribe(harness.waiter(), channel: b, topic: "b")) == [
        .publishChannelStatus(b, .subscribing(attempt: 1)),
        .fetchAccessToken(generation: 2),
      ])

    #expect(harness.send(.tokenFetched(token: "t1", generation: 1)) == [])
    #expect(harness.core.channels[b]?.phase == .refreshingToken(attempt: 1))
    #expect(harness.core.tokenFetchGeneration == 2)

    #expect(
      harness.send(.tokenFetched(token: "t2", generation: 2)) == [
        .send(try Self.join(ref: "2", token: "t2", topic: "b")),
        .schedule(.joinTimeout(channel: b, ref: "2"), after: .seconds(10)),
        .send(Self.accessToken("t2", joinRef: "1", ref: "3", topic: "a")),
      ])
    #expect(harness.core.tokens.token == "t2")
    #expect(harness.send(.tokenFetched(token: "t9", generation: 2)) == [])
  }

  // MARK: Refresh timer

  @Test
  func refreshTimerScheduledBeforeExpiry() {
    var harness = CoreHarness.connected(options: Self.withProvider)

    #expect(
      harness.send(.setAuth(token: makeJWT(exp: 3600)))
        == [.schedule(.tokenRefresh, after: .seconds(3540))])
    // Never sooner than the refresh interval.
    #expect(
      harness.send(.setAuth(token: makeJWT(exp: 30)))
        == [.schedule(.tokenRefresh, after: .seconds(10))])
    // A token without `exp` has nothing to plan around.
    #expect(harness.send(.setAuth(token: "opaque")) == [.cancel(.tokenRefresh)])
    #expect(harness.send(.setAuth(token: makeJWT(exp: 3600))).count == 1)

    #expect(harness.send(.timerFired(.tokenRefresh)) == [.fetchAccessToken(generation: 5)])
    #expect(
      harness.send(.tokenFetched(token: makeJWT(exp: 7200), generation: 5))
        == [.schedule(.tokenRefresh, after: .seconds(7140))])

    let disconnected = harness.send(.disconnectRequested(code: nil, reason: nil))
    #expect(disconnected.contains(.cancel(.tokenRefresh)))
    #expect(harness.send(.timerFired(.tokenRefresh)) == [])
    #expect(harness.send(.setAuth(token: makeJWT(exp: 9000))) == [])
  }

  @Test
  func refreshTimerIsCancelledWhenTheSocketDrops() {
    var harness = CoreHarness.connected(options: Self.withProvider)
    _ = harness.send(.setAuth(token: makeJWT(exp: 3600)))

    #expect(harness.send(.socketClosed(code: 1006, reason: nil)).contains(.cancel(.tokenRefresh)))
  }

  @Test
  func reconnectSchedulesTheRefreshTimerAgain() throws {
    var harness = CoreHarness.connected(options: Self.withProvider)
    _ = harness.send(.setAuth(token: makeJWT(exp: 3600)))
    _ = harness.send(.disconnectRequested(code: nil, reason: nil))
    _ = harness.send(.connect(waiter: nil))

    let socket = FakeWebSocket.fakes().0
    let effects = harness.send(.socketOpened(socket))

    #expect(effects.contains(.schedule(.tokenRefresh, after: .seconds(3540))))
  }

  @Test
  func refreshTimerWhileDisconnectedDoesNotFetch() {
    var harness = CoreHarness(options: Self.withProvider)

    #expect(harness.send(.timerFired(.tokenRefresh)) == [])
  }

  @Test
  func heartbeatTriggersTokenRefresh() {
    var harness = CoreHarness.connected(options: Self.withProvider)

    #expect(
      harness.send(.timerFired(.heartbeat)) == [
        .send(Self.heartbeat(ref: "1")), .publishHeartbeat(.sent),
        .schedule(.heartbeat, after: .seconds(25)), .fetchAccessToken(generation: 1),
      ])
    _ = harness.send(.tokenFetched(token: "t1", generation: 1))
    _ = harness.send(.frame(Self.heartbeatReply(ref: "1")))

    harness.advance(by: .seconds(5))
    #expect(
      harness.send(.timerFired(.heartbeat)) == [
        .send(Self.heartbeat(ref: "2")), .publishHeartbeat(.sent),
        .schedule(.heartbeat, after: .seconds(25)),
      ])
  }

  // MARK: Leaving the refreshingToken phase

  @Test
  func socketLossMovesARefreshingChannelToWaitForTheSocket() throws {
    var harness = CoreHarness.connected(options: Self.withProvider)
    _ = harness.send(Self.subscribe(harness.waiter()))

    _ = harness.send(.socketClosed(code: 1006, reason: nil))
    #expect(harness.core.channels[.room]?.phase == .waitingForSocket(attempt: 1))
    // The fetch ends while the socket is down: nothing joins.
    #expect(harness.send(.tokenFetched(token: "t1", generation: 1)) == [])

    _ = harness.send(.retryTimerFired)
    let opened = harness.send(.socketOpened(FakeWebSocket.fakes().0))
    #expect(opened.contains(.send(try Self.join(ref: "1", token: "t1"))))
  }

  @Test
  func serverAuthCloseFailsARefreshingSubscribe() {
    var harness = CoreHarness.connected(options: Self.withProvider)
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w))
    let closed = RealtimeError.socketClosed(
      code: WebSocketCloseCode(rawValue: 4001), reason: "jwt expired")

    let effects = harness.send(.socketClosed(code: 4001, reason: "jwt expired"))

    #expect(
      Array(effects.suffix(2)) == [
        .resume(w, .failure(closed)),
        .publishChannelStatus(.room, .failed(closed)),
      ])
    #expect(harness.core.channels[.room]?.phase == .failed(closed))
  }

  @Test
  func unsubscribeOrRemoveWhileRefreshingSendsNoJoinLater() {
    var harness = CoreHarness.connected(options: Self.withProvider)
    let a = harness.channel()
    let b = harness.channel()
    let wa = harness.waiter()
    let wb = harness.waiter()
    _ = harness.send(Self.subscribe(wa, channel: a, topic: "a"))
    _ = harness.send(Self.subscribe(wb, channel: b, topic: "b"))

    let unsubscribe = harness.waiter()
    #expect(
      harness.send(.unsubscribe(channel: a, waiter: unsubscribe)) == [
        .resume(wa, .cancelled),
        .publishChannelStatus(a, .unsubscribed),
        .resume(unsubscribe, .success),
      ])
    let remove = harness.waiter()
    #expect(
      harness.send(.removeChannel(channel: b, waiter: remove)) == [
        .resume(wb, .failure(.channelRemoved)),
        .publishChannelStatus(b, .unsubscribed),
        .resume(remove, .success),
        .finishChannel(b),
      ])

    #expect(harness.send(.tokenFetched(token: "t1", generation: 1)) == [])
    #expect(harness.core.channels[a]?.phase == .unsubscribed)
    #expect(harness.core.channels[b] == nil)
  }

  /// A channel waiting for a token has no join the server knows: the first join was not sent
  /// yet, and a rejoin replaces a join the server refused, one that timed out, or one on a
  /// socket that is gone. So presence for the old join is dropped.
  @Test
  func presenceForTheOldJoinIsDroppedWhileRefreshing() throws {
    var harness = CoreHarness.connected(options: Self.withProvider)
    _ = harness.send(Self.subscribe(harness.waiter(), presence: true))
    _ = harness.send(.tokenFetched(token: "t1", generation: 1))
    _ = harness.send(.frame(Self.reply(ref: "1", error: Self.expired)))
    #expect(harness.core.channels[.room]?.currentJoinRef == nil)

    #expect(harness.send(.frame(Self.presenceState(joinRef: "1"))) == [])
    #expect(harness.core.channels[.room]?.presence.state == PresenceState())

    _ = harness.send(.tokenFetched(token: "t2", generation: 2))
    #expect(harness.send(.frame(Self.presenceState(joinRef: "2"))).count == 1)
  }

  @Test
  func rejoinAfterJoinTimeoutForgetsTheTimedOutJoinWhileRefreshing() {
    var harness = CoreHarness.connected(options: Self.withProvider)
    _ = harness.send(Self.subscribe(harness.waiter()))
    _ = harness.send(.tokenFetched(token: "t1", generation: 1))
    _ = harness.send(.timerFired(.joinTimeout(channel: .room, ref: "1")))
    #expect(harness.core.channels[.room]?.currentJoinRef == "1")

    harness.advance(by: .seconds(10))
    #expect(
      harness.send(.timerFired(.rejoin(channel: .room))) == [
        .publishChannelStatus(.room, .subscribing(attempt: 2)),
        .fetchAccessToken(generation: 2),
      ])
    #expect(harness.core.channels[.room]?.currentJoinRef == nil)
    #expect(harness.send(.frame(Self.reply(ref: "1"))) == [])
  }

  // MARK: Helpers

  static func subscribe(
    _ waiter: WaiterID, channel: ChannelID = .room, topic: String = topic, presence: Bool = false
  ) -> Event {
    .subscribe(
      channel: channel, topic: topic, configuration: RealtimeChannelConfiguration(), waiter: waiter,
      snapshot: JoinSnapshot(bindings: [], presenceEnabled: presence))
  }

  static func join(ref: Ref, token: String?, topic: String = topic) throws -> RealtimeMessage {
    let payload = RealtimeJoinPayload(
      config: RealtimeJoinConfig(
        RealtimeChannelConfiguration(), bindings: [], presenceEnabled: false),
      accessToken: token, version: nil)
    return RealtimeMessage(
      joinRef: ref, ref: ref, topic: "realtime:\(topic)", event: "phx_join",
      payload: try JSONObject(payload))
  }

  static func reply(
    ref: Ref, error: RealtimeError? = nil, topic: String = topic
  ) -> RealtimeMessage {
    let payload: JSONObject =
      if let error {
        ["status": "error", "response": ["reason": .string(error.message)]]
      } else {
        ["status": "ok", "response": [:]]
      }
    return RealtimeMessage(
      joinRef: ref, ref: ref, topic: "realtime:\(topic)", event: "phx_reply", payload: payload)
  }

  static func accessToken(
    _ token: String, joinRef: Ref, ref: Ref, topic: String = topic
  ) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: joinRef, ref: ref, topic: "realtime:\(topic)", event: "access_token",
      payload: ["access_token": .string(token)])
  }

  static func presenceState(joinRef: Ref) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: joinRef, ref: nil, topic: "realtime:\(topic)", event: "presence_state",
      payload: ["alice": ["metas": [["phx_ref": "a1"]]]])
  }

  static func heartbeat(ref: Ref) -> RealtimeMessage {
    RealtimeMessage(joinRef: nil, ref: ref, topic: "phoenix", event: "heartbeat", payload: [:])
  }

  static func heartbeatReply(ref: Ref) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: nil, ref: ref, topic: "phoenix", event: "phx_reply",
      payload: ["status": "ok", "response": [:]])
  }
}
