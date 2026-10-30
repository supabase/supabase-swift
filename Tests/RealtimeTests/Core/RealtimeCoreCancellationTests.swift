//
//  RealtimeCoreCancellationTests.swift
//  RealtimeTests
//

import Foundation
import Helpers
import TestHelpers
import Testing

@testable import Realtime

/// A caller of ``RealtimeCore`` whose task is cancelled: its waiter resumes `.cancelled` once,
/// and only the last subscribe caller of a join in flight rolls the join back.
@Suite
struct RealtimeCoreCancellationTests {
  typealias Event = RealtimeCore.Event
  typealias Effect = RealtimeCore.Effect

  static let topic = "room"
  static let noStreams = JoinSnapshot(bindings: [], presenceEnabled: false)
  static let messages = PostgresJoinConfig(event: .insert, schema: "public", table: "messages")

  // MARK: Subscribe

  @Test
  func lastSubscribeWaiterCancelledRollsBack() {
    var harness = CoreHarness.connected()
    let w1 = harness.waiter()
    _ = harness.send(Self.subscribe(w1))

    #expect(
      harness.send(.waiterCancelled(w1)) == [
        .resume(w1, .cancelled),
        .send(Self.leave(joinRef: "1", ref: "2")),
        .publishChannelStatus(Self.topic, .unsubscribed),
        .cancel(.joinTimeout(topic: Self.topic, ref: "1")),
      ])
    #expect(harness.core.channels[Self.topic]?.phase == .unsubscribed)
    #expect(harness.send(.waiterCancelled(w1)) == [])
    #expect(harness.send(.frame(Self.reply(ref: "1"))) == [])
    #expect(harness.send(.timerFired(.joinTimeout(topic: Self.topic, ref: "1"))) == [])
  }

  @Test
  func rollbackBeforeJoinSentSendsNoLeave() {
    var harness = CoreHarness()
    let socket = FakeWebSocket.fakes().0
    let w1 = harness.waiter()
    _ = harness.send(Self.subscribe(w1))
    #expect(harness.core.channels[Self.topic]?.phase == .waitingForSocket(attempt: 1))

    #expect(
      harness.send(.waiterCancelled(w1)) == [
        .resume(w1, .cancelled),
        .publishChannelStatus(Self.topic, .unsubscribed),
      ])
    // The connect the subscribe started goes on, but the channel no longer joins.
    #expect(
      harness.send(.socketOpened(socket)) == [
        .publishClientStatus(.connected),
        .installSocket(socket, rejoinChannels: false),
        .schedule(.heartbeat, after: .seconds(25)),
      ])
    #expect(harness.core.channels[Self.topic]?.phase == .unsubscribed)
  }

  @Test
  func rollbackWhileRefreshingTokenDoesNotJoinOnTheToken() {
    var options = RealtimeCore.Options.test
    options.hasAccessTokenProvider = true
    var harness = CoreHarness.connected(options: options)
    let w1 = harness.waiter()
    _ = harness.send(Self.subscribe(w1))
    #expect(harness.core.channels[Self.topic]?.phase == .refreshingToken(attempt: 1))

    #expect(
      harness.send(.waiterCancelled(w1)) == [
        .resume(w1, .cancelled),
        .publishChannelStatus(Self.topic, .unsubscribed),
      ])
    #expect(harness.send(.tokenFetched(token: "t1", generation: 1)) == [])
    #expect(harness.core.channels[Self.topic]?.phase == .unsubscribed)
  }

  @Test
  func rollbackWhileWaitingForPostgresLeaves() {
    var harness = CoreHarness.connected()
    let w1 = harness.waiter()
    _ = harness.send(
      .subscribe(
        topic: Self.topic, configuration: RealtimeChannelConfiguration(), waiter: w1,
        snapshot: JoinSnapshot(bindings: [Self.messages], presenceEnabled: false)))
    _ = harness.send(.frame(Self.reply(ref: "1")))
    #expect(
      harness.core.channels[Self.topic]?.phase == .joining(ref: "1", attempt: 1, stage: .postgres))

    #expect(
      harness.send(.waiterCancelled(w1)) == [
        .resume(w1, .cancelled),
        .send(Self.leave(joinRef: "1", ref: "2")),
        .publishChannelStatus(Self.topic, .unsubscribed),
        .cancel(.postgresTimeout(topic: Self.topic, ref: "1")),
      ])
    #expect(harness.send(.frame(Self.system(joinRef: "1"))) == [])
    #expect(harness.core.channels[Self.topic]?.phase == .unsubscribed)
  }

  @Test
  func rollbackDuringBackoffLeavesTheTimedOutJoin() {
    var harness = CoreHarness.connected()
    let w1 = harness.waiter()
    _ = harness.send(Self.subscribe(w1))
    _ = harness.send(.timerFired(.joinTimeout(topic: Self.topic, ref: "1")))

    #expect(
      harness.send(.waiterCancelled(w1)) == [
        .resume(w1, .cancelled),
        .send(Self.leave(joinRef: "1", ref: "2")),
        .publishChannelStatus(Self.topic, .unsubscribed),
        .cancel(.rejoin(topic: Self.topic)),
      ])
    #expect(harness.send(.frame(Self.reply(ref: "1"))) == [])
    #expect(harness.send(.timerFired(.rejoin(topic: Self.topic))) == [])
    #expect(harness.core.channels[Self.topic]?.phase == .unsubscribed)
  }

  @Test
  func rollbackDuringBackoffAfterARefusedJoinSendsNoLeave() {
    var harness = CoreHarness.connected()
    let w1 = harness.waiter()
    _ = harness.send(Self.subscribe(w1))
    _ = harness.send(.frame(Self.refusal(ref: "1")))
    #expect(harness.core.channels[Self.topic]?.timedOutJoinRef == nil)

    #expect(
      harness.send(.waiterCancelled(w1)) == [
        .resume(w1, .cancelled),
        .publishChannelStatus(Self.topic, .unsubscribed),
        .cancel(.rejoin(topic: Self.topic)),
      ])
  }

  @Test
  func otherWaitersKeepTheAttempt() {
    var harness = CoreHarness.connected()
    let w1 = harness.waiter()
    let w2 = harness.waiter()
    _ = harness.send(Self.subscribe(w1))
    _ = harness.send(Self.subscribe(w2))

    #expect(harness.send(.waiterCancelled(w1)) == [.resume(w1, .cancelled)])
    #expect(
      harness.core.channels[Self.topic]?.phase == .joining(ref: "1", attempt: 1, stage: .reply))
    #expect(
      harness.send(.frame(Self.reply(ref: "1"))) == [
        .resume(w2, .success),
        .publishChannelStatus(Self.topic, .subscribed),
        .cancel(.joinTimeout(topic: Self.topic, ref: "1")),
      ])
  }

  @Test
  func cancelAfterSubscribedDoesNothing() {
    var harness = Self.subscribed()

    #expect(harness.send(.waiterCancelled(WaiterID(rawValue: 1))) == [])
    #expect(harness.send(.waiterCancelled(WaiterID(rawValue: 99))) == [])
    #expect(harness.core.channels[Self.topic]?.phase == .subscribed(joinRef: "1"))
  }

  @Test
  func cancelDuringAnAutomaticRejoinKeepsIt() {
    var harness = Self.subscribed()
    _ = harness.send(.socketClosed(code: 1001, reason: nil))
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w))

    #expect(harness.send(.waiterCancelled(w)) == [.resume(w, .cancelled)])
    #expect(harness.core.channels[Self.topic]?.phase == .waitingForSocket(attempt: 1))
  }

  @Test
  func cancelDuringABindingsRejoinKeepsIt() {
    var harness = Self.subscribed()
    _ = harness.send(
      .bindingsChanged(
        topic: Self.topic,
        snapshot: JoinSnapshot(bindings: [Self.messages], presenceEnabled: false)))
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w))

    #expect(harness.send(.waiterCancelled(w)) == [.resume(w, .cancelled)])
    #expect(
      harness.core.channels[Self.topic]?.phase == .joining(ref: "3", attempt: 1, stage: .reply))
  }

  @Test
  func subscribeAfterAnAutomaticRejoinEndedRollsBack() {
    var harness = Self.subscribed()
    _ = harness.send(.socketClosed(code: 1001, reason: nil))
    _ = harness.send(.disconnectRequested(code: nil, reason: nil))
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w))

    #expect(
      harness.send(.waiterCancelled(w)) == [
        .resume(w, .cancelled),
        .publishChannelStatus(Self.topic, .unsubscribed),
      ])
  }

  @Test
  func cancelledSubscribeDuringLeaveDoesNotJoinAgain() {
    var harness = Self.subscribed()
    let leaver = harness.waiter()
    let subscriber = harness.waiter()
    _ = harness.send(.unsubscribe(topic: Self.topic, waiter: leaver))
    _ = harness.send(Self.subscribe(subscriber))

    #expect(harness.send(.waiterCancelled(subscriber)) == [.resume(subscriber, .cancelled)])
    #expect(
      harness.send(.frame(Self.close(joinRef: "1"))) == [
        .resume(leaver, .success),
        .publishChannelStatus(Self.topic, .unsubscribed),
        .cancel(.leaveTimeout(topic: Self.topic, ref: "2")),
      ])
  }

  // MARK: Pushes

  @Test
  func cancelledAckPushDropsLateReply() {
    var configuration = RealtimeChannelConfiguration()
    configuration.broadcast.acknowledge = true
    var harness = Self.subscribed(configuration: configuration)
    let w = harness.waiter()
    _ = harness.send(
      .broadcast(topic: Self.topic, event: "cursor", payload: .json(["x": 1]), waiter: w))

    #expect(
      harness.send(.waiterCancelled(w)) == [
        .resume(w, .cancelled),
        .cancel(.pushTimeout(topic: Self.topic, ref: "2")),
      ])
    #expect(harness.core.channels[Self.topic]?.pendingPushes.isEmpty == true)
    #expect(harness.send(.frame(Self.reply(ref: "2", joinRef: "1"))) == [])
    #expect(harness.send(.timerFired(.pushTimeout(topic: Self.topic, ref: "2"))) == [])
  }

  // MARK: Unsubscribe and removeChannel

  @Test
  func cancelledUnsubscribeStillLeaves() {
    var harness = Self.subscribed()
    let w = harness.waiter()
    _ = harness.send(.unsubscribe(topic: Self.topic, waiter: w))

    #expect(harness.send(.waiterCancelled(w)) == [.resume(w, .cancelled)])
    #expect(harness.core.channels[Self.topic]?.phase == .leaving(joinRef: "1", leaveRef: "2"))
    #expect(
      harness.send(.frame(Self.close(joinRef: "1"))) == [
        .publishChannelStatus(Self.topic, .unsubscribed),
        .cancel(.leaveTimeout(topic: Self.topic, ref: "2")),
      ])
  }

  @Test
  func cancelledRemoveStillRemoves() {
    var harness = Self.subscribed()
    let w = harness.waiter()
    _ = harness.send(.removeChannel(topic: Self.topic, waiter: w))

    #expect(harness.send(.waiterCancelled(w)) == [.resume(w, .cancelled)])
    #expect(
      harness.send(.frame(Self.close(joinRef: "1"))) == [
        .publishChannelStatus(Self.topic, .unsubscribed),
        .cancel(.leaveTimeout(topic: Self.topic, ref: "2")),
        .finishChannel(Self.topic),
        .scheduleIdleDisconnect(after: .seconds(50)),
      ])
    #expect(harness.core.channels[Self.topic] == nil)
  }

  // MARK: Connect

  @Test
  func cancelledConnectWaiterKeepsConnecting() {
    var harness = CoreHarness()
    let socket = FakeWebSocket.fakes().0
    let w = harness.waiter()
    _ = harness.send(.connect(waiter: w))

    #expect(harness.send(.waiterCancelled(w)) == [.resume(w, .cancelled)])
    #expect(harness.core.connection == .connecting(attempt: 1))
    #expect(
      harness.send(.socketOpened(socket)) == [
        .publishClientStatus(.connected),
        .installSocket(socket, rejoinChannels: false),
        .schedule(.heartbeat, after: .seconds(25)),
      ])
  }

  // MARK: Helpers

  static func subscribe(_ waiter: WaiterID) -> Event {
    .subscribe(
      topic: topic, configuration: RealtimeChannelConfiguration(), waiter: waiter,
      snapshot: noStreams)
  }

  /// A connected harness whose channel joined with ref `"1"`. It used waiter id 1.
  static func subscribed(
    configuration: RealtimeChannelConfiguration = RealtimeChannelConfiguration()
  ) -> CoreHarness {
    var harness = CoreHarness.connected()
    _ = harness.send(
      .subscribe(
        topic: topic, configuration: configuration, waiter: harness.waiter(),
        snapshot: noStreams))
    _ = harness.send(.frame(reply(ref: "1")))
    return harness
  }

  static func reply(ref: Ref, joinRef: Ref? = nil) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: joinRef ?? ref, ref: ref, topic: "realtime:\(topic)", event: "phx_reply",
      payload: ["status": "ok", "response": [:]])
  }

  /// A retryable refusal of the join `ref`.
  static func refusal(ref: Ref) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: ref, ref: ref, topic: "realtime:\(topic)", event: "phx_reply",
      payload: ["status": "error", "response": ["reason": "UnknownErrorOnChannel: boom"]])
  }

  static func leave(joinRef: Ref, ref: Ref) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: joinRef, ref: ref, topic: "realtime:\(topic)", event: "phx_leave", payload: [:])
  }

  static func close(joinRef: Ref?) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: joinRef, ref: nil, topic: "realtime:\(topic)", event: "phx_close", payload: [:])
  }

  static func system(joinRef: Ref?) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: joinRef, ref: nil, topic: "realtime:\(topic)", event: "system",
      payload: [
        "status": "ok", "extension": "postgres_changes", "message": "Subscribed to PostgreSQL",
      ])
  }
}
