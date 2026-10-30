//
//  RealtimeCoreLeaveTests.swift
//  RealtimeTests
//

import Foundation
import Helpers
import TestHelpers
import Testing

@testable import Realtime

/// How a channel of ``RealtimeCore`` ends or loses its join: `unsubscribe`, the server's
/// `phx_close` and `phx_error`, a socket that goes away, and `disconnect()`.
@Suite
struct RealtimeCoreLeaveTests {
  typealias Event = RealtimeCore.Event
  typealias Effect = RealtimeCore.Effect

  static let topic = "room"
  static let noStreams = JoinSnapshot(bindings: [], presenceEnabled: false)

  // MARK: Unsubscribe

  @Test
  func unsubscribeFromSubscribedSendsLeaveAndWaitsForClose() {
    var harness = Self.subscribed()
    let w = harness.waiter()

    #expect(
      harness.send(.unsubscribe(topic: Self.topic, waiter: w)) == [
        .send(Self.leave(joinRef: "1", ref: "2")),
        .publishChannelStatus(Self.topic, .unsubscribing),
        .schedule(.leaveTimeout(topic: Self.topic, ref: "2"), after: .seconds(10)),
      ])
    #expect(harness.core.channels[Self.topic]?.phase == .leaving(joinRef: "1", leaveRef: "2"))

    #expect(
      harness.send(.frame(Self.close(joinRef: "1"))) == [
        .resume(w, .success),
        .publishChannelStatus(Self.topic, .unsubscribed),
        .cancel(.leaveTimeout(topic: Self.topic, ref: "2")),
      ])
    #expect(harness.core.channels[Self.topic]?.phase == .unsubscribed)
  }

  @Test
  func leaveTimeoutCompletesUnsubscribe() {
    var harness = Self.subscribed()
    let w = harness.waiter()
    _ = harness.send(.unsubscribe(topic: Self.topic, waiter: w))

    #expect(harness.send(.timerFired(.leaveTimeout(topic: Self.topic, ref: "9"))) == [])
    #expect(
      harness.send(.timerFired(.leaveTimeout(topic: Self.topic, ref: "2"))) == [
        .resume(w, .success),
        .publishChannelStatus(Self.topic, .unsubscribed),
      ])
    // The leave is over, so a late close is for a join the channel no longer has.
    #expect(harness.send(.frame(Self.close(joinRef: "1"))) == [])
    #expect(harness.core.channels[Self.topic]?.phase == .unsubscribed)
  }

  @Test
  func unsubscribeWhileJoiningSendsLeaveWithoutWaiting() {
    var harness = CoreHarness.connected()
    let first = harness.waiter()
    let second = harness.waiter()
    _ = harness.send(Self.subscribe(first))
    _ = harness.send(Self.subscribe(second))
    let w = harness.waiter()

    #expect(
      harness.send(.unsubscribe(topic: Self.topic, waiter: w)) == [
        .send(Self.leave(joinRef: "1", ref: "2")),
        .resume(first, .cancelled),
        .resume(second, .cancelled),
        .publishChannelStatus(Self.topic, .unsubscribed),
        .cancel(.joinTimeout(topic: Self.topic, ref: "1")),
        .resume(w, .success),
      ])
    #expect(harness.send(.frame(Self.reply(ref: "1"))) == [])
  }

  @Test
  func unsubscribeWhileSocketDownSkipsLeave() {
    var harness = Self.subscribed()
    _ = harness.send(.socketClosed(code: 1001, reason: nil))
    let w = harness.waiter()

    #expect(
      harness.send(.unsubscribe(topic: Self.topic, waiter: w)) == [
        .publishChannelStatus(Self.topic, .unsubscribed),
        .resume(w, .success),
      ])
  }

  @Test
  func unsubscribeReportsEveryPresenceAsALeave() throws {
    var harness = Self.subscribed()
    // Inbound presence comes with Task 9.
    var presence = try #require(harness.core.channels[Self.topic]?.presence)
    let joined = presence.applyState(["ana": ["metas": [["phx_ref": "r1"]]]])
    harness.core.channels[Self.topic]?.presence = presence
    let w = harness.waiter()

    let effects = harness.send(.unsubscribe(topic: Self.topic, waiter: w))

    #expect(
      effects.first
        == .deliver(Self.topic, .presence(PresenceChange(leaves: joined.joins), PresenceState())))
    #expect(harness.core.channels[Self.topic]?.presence.state == PresenceState())
  }

  @Test
  func unsubscribeWithoutAJoinSucceeds() {
    var harness = CoreHarness.connected()
    let w = harness.waiter()

    #expect(harness.send(.unsubscribe(topic: Self.topic, waiter: w)) == [.resume(w, .success)])
  }

  @Test
  func subscribeDuringLeaveJoinsWhenTheLeaveEnds() throws {
    var harness = Self.subscribed()
    let leaver = harness.waiter()
    let subscriber = harness.waiter()
    _ = harness.send(.unsubscribe(topic: Self.topic, waiter: leaver))

    #expect(harness.send(Self.subscribe(subscriber)) == [])
    #expect(
      harness.send(.frame(Self.close(joinRef: "1"))) == [
        .resume(leaver, .success),
        .publishChannelStatus(Self.topic, .unsubscribed),
        .cancel(.leaveTimeout(topic: Self.topic, ref: "2")),
        .publishChannelStatus(Self.topic, .subscribing(attempt: 1)),
        .send(try Self.join(ref: "3")),
        .schedule(.joinTimeout(topic: Self.topic, ref: "3"), after: .seconds(10)),
      ])
    // `unsubscribe` made the next join a new subscription, not a rejoin.
    #expect(
      harness.send(.frame(Self.reply(ref: "3"))) == [
        .resume(subscriber, .success),
        .publishChannelStatus(Self.topic, .subscribed),
        .cancel(.joinTimeout(topic: Self.topic, ref: "3")),
      ])
  }

  @Test
  func unsubscribeDuringLeaveCancelsTheQueuedSubscribe() {
    var harness = Self.subscribed()
    let leaver = harness.waiter()
    let subscriber = harness.waiter()
    let lastLeaver = harness.waiter()
    _ = harness.send(.unsubscribe(topic: Self.topic, waiter: leaver))
    _ = harness.send(Self.subscribe(subscriber))

    #expect(
      harness.send(.unsubscribe(topic: Self.topic, waiter: lastLeaver)) == [
        .resume(subscriber, .cancelled)
      ])
    #expect(
      harness.send(.timerFired(.leaveTimeout(topic: Self.topic, ref: "2"))) == [
        .resume(leaver, .success),
        .resume(lastLeaver, .success),
        .publishChannelStatus(Self.topic, .unsubscribed),
      ])
  }

  // MARK: Server close

  @Test
  func serverCloseWhileJoiningFailsWithChannelClosedByServer() {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w))

    #expect(
      harness.send(.frame(Self.close(joinRef: "1"))) == [
        .resume(w, .failure(.channelClosedByServer)),
        .publishChannelStatus(Self.topic, .failed(.channelClosedByServer)),
        .cancel(.joinTimeout(topic: Self.topic, ref: "1")),
        .finishChannel(Self.topic),
      ])
    #expect(harness.core.channels[Self.topic] == nil)
  }

  @Test
  func serverCloseWhileSubscribedUnsubscribes() {
    var harness = Self.subscribed()

    #expect(
      harness.send(.frame(Self.close(joinRef: nil))) == [
        .publishChannelStatus(Self.topic, .unsubscribed),
        .finishChannel(Self.topic),
      ])
    #expect(harness.core.channels[Self.topic] == nil)
  }

  /// `phx_error` ends the join like `phx_close`, but the channel stays, as today.
  @Test
  func serverErrorUnsubscribesAndKeepsTheChannel() {
    var harness = Self.subscribed()

    #expect(
      harness.send(.frame(Self.error(joinRef: "1"))) == [
        .publishChannelStatus(Self.topic, .unsubscribed)
      ])
    #expect(harness.core.channels[Self.topic]?.phase == .unsubscribed)
  }

  @Test
  func staleCloseIsIgnored() {
    var harness = Self.subscribed()
    _ = harness.send(.socketClosed(code: 1001, reason: nil))
    _ = harness.send(.retryTimerFired)
    _ = harness.send(.socketOpened(FakeWebSocket.fakes().0))
    _ = harness.send(.frame(Self.reply(ref: "2")))

    #expect(harness.send(.frame(Self.close(joinRef: "1"))) == [])
    #expect(harness.send(.frame(Self.error(joinRef: "1"))) == [])
    #expect(harness.core.channels[Self.topic]?.phase == .subscribed(joinRef: "2"))
  }

  // MARK: Socket loss

  @Test
  func subscribeWaiterSurvivesSocketDropAndWake() throws {
    var harness = CoreHarness.connected()
    let socket = try #require(harness.socket)
    let w = harness.waiter()
    let push = harness.waiter()
    _ = harness.send(Self.subscribe(w))
    // The drop fails whatever waits for a reply.
    harness.core.channels[Self.topic]?.pendingPushes["7"] = push
    _ = harness.send(.appBackground)

    #expect(
      harness.send(.socketFailed(.heartbeatTimeout)) == [
        .publishClientStatus(
          .reconnecting(attempt: 1, retryIn: .seconds(1), lastError: .heartbeatTimeout)),
        .closeSocket(socket, code: 1001, reason: "error: heartbeat timeout"),
        .stopSocketLoops,
        .scheduleRetry(after: .seconds(1)),
        .cancel(.heartbeat),
        .resume(push, .failure(.notConnected)),
        .cancel(.pushTimeout(topic: Self.topic, ref: "7")),
        .cancel(.joinTimeout(topic: Self.topic, ref: "1")),
      ])
    #expect(harness.core.channels[Self.topic]?.phase == .waitingForSocket(attempt: 1))
    #expect(harness.core.channels[Self.topic]?.subscribeWaiters == [w])
    #expect(harness.core.channels[Self.topic]?.pendingPushes.isEmpty == true)

    #expect(
      harness.send(.appForeground) == [
        .publishClientStatus(.connecting(attempt: 2)), .cancelRetry, .openSocket,
      ])
    let next = FakeWebSocket.fakes().0
    #expect(
      harness.send(.socketOpened(next)) == [
        .publishClientStatus(.connected),
        .installSocket(next, rejoinChannels: true),
        .schedule(.heartbeat, after: .seconds(25)),
        .send(try Self.join(ref: "2")),
        .schedule(.joinTimeout(topic: Self.topic, ref: "2"), after: .seconds(10)),
      ])
    #expect(
      harness.send(.frame(Self.reply(ref: "2"))) == [
        .resume(w, .success),
        .publishChannelStatus(Self.topic, .subscribed),
        .cancel(.joinTimeout(topic: Self.topic, ref: "2")),
      ])
  }

  @Test
  func subscribedChannelRejoinsAfterReconnect() throws {
    var harness = Self.subscribed()

    let dropped = harness.send(.socketClosed(code: 1001, reason: nil))
    #expect(dropped.last == .publishChannelStatus(Self.topic, .subscribing(attempt: 1)))
    #expect(harness.core.channels[Self.topic]?.phase == .waitingForSocket(attempt: 1))

    _ = harness.send(.retryTimerFired)
    let next = FakeWebSocket.fakes().0
    let opened = harness.send(.socketOpened(next))
    #expect(opened.contains(.installSocket(next, rejoinChannels: true)))
    #expect(opened.contains(.send(try Self.join(ref: "2"))))
    #expect(
      harness.send(.frame(Self.reply(ref: "2"))) == [
        .publishChannelStatus(Self.topic, .subscribed),
        .deliver(Self.topic, .event(.resubscribed)),
        .cancel(.joinTimeout(topic: Self.topic, ref: "2")),
      ])
  }

  /// The core rejoins on reconnect itself, so `installSocket(rejoinChannels: true)` must not
  /// lead to a second join.
  @Test
  func reconnectSendsOneJoinPerChannel() {
    var harness = Self.subscribed()
    _ = harness.send(
      .subscribe(
        topic: "other", configuration: RealtimeChannelConfiguration(),
        waiter: harness.waiter(), snapshot: Self.noStreams))
    _ = harness.send(.timerFired(.joinTimeout(topic: "other", ref: "2")))
    _ = harness.send(.socketClosed(code: 1001, reason: nil))
    _ = harness.send(.retryTimerFired)

    let opened = harness.send(.socketOpened(FakeWebSocket.fakes().0))

    let joins = opened.compactMap { effect -> String? in
      guard case .send(let message) = effect, message.event == ChannelEvent.join else {
        return nil
      }
      return message.topic
    }
    #expect(joins == ["realtime:other", "realtime:room"])
    #expect(harness.core.channels["other"]?.phase == .joining(ref: "3", attempt: 2, stage: .reply))
  }

  @Test
  func socketLossKeepsAWaitingChannelWaiting() {
    var harness = CoreHarness()
    let w = harness.waiter()
    _ = harness.send(.connect(waiter: nil))
    _ = harness.send(Self.subscribe(w))

    #expect(harness.send(.socketClosed(code: 1001, reason: nil)) == [])
    #expect(harness.send(.socketFailed(.heartbeatTimeout)) == [])
    #expect(harness.core.channels[Self.topic]?.phase == .waitingForSocket(attempt: 1))
    #expect(harness.core.channels[Self.topic]?.subscribeWaiters == [w])
  }

  @Test
  func socketLossEndsALeave() {
    var harness = Self.subscribed()
    let w = harness.waiter()
    _ = harness.send(.unsubscribe(topic: Self.topic, waiter: w))

    let effects = harness.send(.socketClosed(code: 1001, reason: nil))

    #expect(
      Array(effects.suffix(3)) == [
        .resume(w, .success),
        .publishChannelStatus(Self.topic, .unsubscribed),
        .cancel(.leaveTimeout(topic: Self.topic, ref: "2")),
      ])
    #expect(harness.core.channels[Self.topic]?.phase == .unsubscribed)
  }

  /// Ruling 8: a channel that lost its socket rejoins once the app comes back and connects
  /// again.
  @Test
  func foregroundAfterTheClientStoppedRejoinsChannels() throws {
    var harness = Self.subscribed()
    _ = harness.send(.appBackground)
    _ = harness.send(.socketClosed(code: 4001, reason: "jwt expired"))
    #expect(harness.core.channels[Self.topic]?.phase == .waitingForSocket(attempt: 1))

    #expect(
      harness.send(.appForeground) == [
        .publishClientStatus(.connecting(attempt: 1)), .openSocket,
      ])
    let next = FakeWebSocket.fakes().0
    let opened = harness.send(.socketOpened(next))
    #expect(opened.contains(.installSocket(next, rejoinChannels: false)))
    #expect(opened.contains(.send(try Self.join(ref: "2"))))
  }

  @Test
  func serverAuthCloseFailsPendingSubscribe() {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w))
    let closed = RealtimeError.socketClosed(
      code: WebSocketCloseCode(rawValue: 4001), reason: "jwt expired")

    let effects = harness.send(.socketClosed(code: 4001, reason: "jwt expired"))

    #expect(
      Array(effects.suffix(3)) == [
        .cancel(.joinTimeout(topic: Self.topic, ref: "1")),
        .resume(w, .failure(closed)),
        .publishChannelStatus(Self.topic, .failed(closed)),
      ])
    #expect(harness.core.channels[Self.topic]?.phase == .failed(closed))
    #expect(harness.core.channels[Self.topic]?.subscribeWaiters.isEmpty == true)
  }

  @Test
  func serverAuthCloseKeepsASubscribedChannelWaitingToRejoin() throws {
    var harness = Self.subscribed()

    _ = harness.send(.socketClosed(code: 4001, reason: "jwt expired"))
    #expect(harness.core.channels[Self.topic]?.phase == .waitingForSocket(attempt: 1))

    _ = harness.send(.connect(waiter: nil))
    let opened = harness.send(.socketOpened(FakeWebSocket.fakes().0))
    #expect(opened.contains(.send(try Self.join(ref: "2"))))
  }

  // MARK: disconnect()

  @Test
  func userDisconnectFailsSubscribeWithDisconnectedWhileSubscribing() throws {
    var harness = CoreHarness.connected()
    let socket = try #require(harness.socket)
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w))

    #expect(
      harness.send(.disconnectRequested(code: nil, reason: nil)) == [
        .publishClientStatus(.disconnected(nil)),
        .cancelAllTasks,
        .closeSocket(socket, code: nil, reason: "Client disconnect"),
        .cancel(.heartbeat),
        .resume(w, .failure(.disconnectedWhileSubscribing)),
        .publishChannelStatus(Self.topic, .unsubscribed),
        .cancel(.joinTimeout(topic: Self.topic, ref: "1")),
      ])
    #expect(harness.core.channels[Self.topic]?.phase == .unsubscribed)
  }

  @Test
  func userDisconnectUnsubscribesSubscribedChannels() {
    var harness = Self.subscribed()

    let effects = harness.send(.disconnectRequested(code: nil, reason: nil))

    #expect(effects.last == .publishChannelStatus(Self.topic, .unsubscribed))
    #expect(harness.core.channels[Self.topic]?.phase == .unsubscribed)
  }

  @Test
  func userDisconnectFailsAChannelWaitingForTheSocket() {
    var harness = CoreHarness()
    let w = harness.waiter()
    _ = harness.send(.connect(waiter: nil))
    _ = harness.send(Self.subscribe(w))

    #expect(
      harness.send(.disconnectRequested(code: nil, reason: nil)) == [
        .publishClientStatus(.disconnected(nil)),
        .cancelAllTasks,
        .resume(w, .failure(.disconnectedWhileSubscribing)),
        .publishChannelStatus(Self.topic, .unsubscribed),
      ])
  }

  // MARK: removeChannel

  @Test
  func removeChannelFailsInFlightSubscribe() {
    var harness = CoreHarness.connected()
    let w1 = harness.waiter()
    let w2 = harness.waiter()
    _ = harness.send(Self.subscribe(w1))

    #expect(
      harness.send(.removeChannel(topic: Self.topic, waiter: w2)) == [
        .send(Self.leave(joinRef: "1", ref: "2")),
        .resume(w1, .failure(.channelRemoved)),
        .publishChannelStatus(Self.topic, .unsubscribing),
        .cancel(.joinTimeout(topic: Self.topic, ref: "1")),
        .schedule(.leaveTimeout(topic: Self.topic, ref: "2"), after: .seconds(10)),
      ])
    #expect(harness.core.channels[Self.topic]?.phase == .leaving(joinRef: "1", leaveRef: "2"))

    #expect(
      harness.send(.frame(Self.close(joinRef: "1"))) == [
        .resume(w2, .success),
        .publishChannelStatus(Self.topic, .unsubscribed),
        .cancel(.leaveTimeout(topic: Self.topic, ref: "2")),
        .finishChannel(Self.topic),
        .scheduleIdleDisconnect(after: .seconds(50)),
      ])
    #expect(harness.core.channels[Self.topic] == nil)
    #expect(harness.send(.frame(Self.reply(ref: "1"))) == [])
  }

  @Test
  func removeChannelOfASubscribedChannelFinishesAfterTheLeaveTimeout() {
    var harness = Self.subscribed()
    let w = harness.waiter()

    #expect(
      harness.send(.removeChannel(topic: Self.topic, waiter: w)) == [
        .send(Self.leave(joinRef: "1", ref: "2")),
        .publishChannelStatus(Self.topic, .unsubscribing),
        .schedule(.leaveTimeout(topic: Self.topic, ref: "2"), after: .seconds(10)),
      ])
    #expect(
      harness.send(.timerFired(.leaveTimeout(topic: Self.topic, ref: "2"))) == [
        .resume(w, .success),
        .publishChannelStatus(Self.topic, .unsubscribed),
        .finishChannel(Self.topic),
        .scheduleIdleDisconnect(after: .seconds(50)),
      ])
    #expect(harness.core.channels[Self.topic] == nil)
  }

  /// A `phx_close` that answers an earlier `unsubscribe()` also ends the removal: the channel
  /// is finished and dropped, which a plain unsubscribe never does.
  @Test
  func removeChannelDuringALeaveFinishesWhenTheCloseArrives() {
    var harness = Self.subscribed()
    let leaver = harness.waiter()
    let remover = harness.waiter()
    _ = harness.send(.unsubscribe(topic: Self.topic, waiter: leaver))

    #expect(harness.send(.removeChannel(topic: Self.topic, waiter: remover)) == [])
    #expect(
      harness.send(.frame(Self.close(joinRef: "1"))) == [
        .resume(leaver, .success),
        .resume(remover, .success),
        .publishChannelStatus(Self.topic, .unsubscribed),
        .cancel(.leaveTimeout(topic: Self.topic, ref: "2")),
        .finishChannel(Self.topic),
        .scheduleIdleDisconnect(after: .seconds(50)),
      ])
    #expect(harness.core.channels[Self.topic] == nil)
  }

  @Test
  func removeChannelWithoutAJoinFinishesAtOnce() {
    var harness = CoreHarness()
    let w1 = harness.waiter()
    let w2 = harness.waiter()
    _ = harness.send(Self.subscribe(w1))

    let effects = harness.send(.removeChannel(topic: Self.topic, waiter: w2))

    #expect(
      effects == [
        .resume(w1, .failure(.channelRemoved)),
        .publishChannelStatus(Self.topic, .unsubscribed),
        .resume(w2, .success),
        .finishChannel(Self.topic),
        .scheduleIdleDisconnect(after: .seconds(50)),
      ])
    #expect(harness.core.channels[Self.topic] == nil)
  }

  @Test
  func removeChannelOfAnUnsubscribedChannelFinishesAtOnce() {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(harness.waiter()))
    _ = harness.send(.unsubscribe(topic: Self.topic, waiter: harness.waiter()))

    #expect(
      harness.send(.removeChannel(topic: Self.topic, waiter: w)) == [
        .resume(w, .success),
        .finishChannel(Self.topic),
        .scheduleIdleDisconnect(after: .seconds(50)),
      ])
  }

  @Test
  func removeChannelOfAnUnknownTopicSucceeds() {
    var harness = CoreHarness.connected()
    let w = harness.waiter()

    #expect(
      harness.send(.removeChannel(topic: Self.topic, waiter: w)) == [
        .resume(w, .success),
        .scheduleIdleDisconnect(after: .seconds(50)),
      ])
  }

  @Test
  func removeChannelCancelsPresenceAndFailsPendingPushes() throws {
    var harness = Self.subscribed()
    let pusher = harness.waiter()
    harness.core.channels[Self.topic]?.pendingPushes["5"] = pusher
    let w = harness.waiter()

    let effects = harness.send(.removeChannel(topic: Self.topic, waiter: w))

    #expect(effects.first == .resume(pusher, .failure(.channelRemoved)))
    #expect(harness.core.channels[Self.topic]?.pendingPushes.isEmpty == true)
  }

  @Test
  func subscribeOnAChannelBeingRemovedFails() {
    var harness = Self.subscribed()
    _ = harness.send(.removeChannel(topic: Self.topic, waiter: harness.waiter()))
    let w = harness.waiter()

    #expect(harness.send(Self.subscribe(w)) == [.resume(w, .failure(.channelRemoved))])
  }

  @Test
  func userDisconnectDuringRemovalFinishesTheChannel() throws {
    var harness = Self.subscribed()
    let socket = try #require(harness.socket)
    let w = harness.waiter()
    _ = harness.send(.removeChannel(topic: Self.topic, waiter: w))

    #expect(
      harness.send(.disconnectRequested(code: nil, reason: nil)) == [
        .publishClientStatus(.disconnected(nil)),
        .cancelAllTasks,
        .closeSocket(socket, code: nil, reason: "Client disconnect"),
        .cancel(.heartbeat),
        .resume(w, .success),
        .publishChannelStatus(Self.topic, .unsubscribed),
        .cancel(.leaveTimeout(topic: Self.topic, ref: "2")),
        .finishChannel(Self.topic),
      ])
    #expect(harness.core.channels[Self.topic] == nil)
  }

  @Test
  func socketLossDuringRemovalFinishesTheChannel() {
    var harness = Self.subscribed()
    let w = harness.waiter()
    _ = harness.send(.removeChannel(topic: Self.topic, waiter: w))

    let effects = harness.send(.socketClosed(code: 1006, reason: nil))

    #expect(effects.contains(.resume(w, .success)))
    #expect(effects.contains(.finishChannel(Self.topic)))
    #expect(harness.core.channels[Self.topic] == nil)
  }

  @Test
  func removingTheLastChannelSchedulesIdleDisconnect() {
    var harness = Self.subscribed()
    let w = harness.waiter()
    _ = harness.send(.removeChannel(topic: Self.topic, waiter: w))

    let effects = harness.send(.frame(Self.close(joinRef: "1")))

    #expect(effects.last == .scheduleIdleDisconnect(after: .seconds(50)))
    #expect(harness.core.idleDisconnectPending)
  }

  @Test
  func removingAChannelWhileAnotherRemainsDoesNotScheduleIdleDisconnect() {
    var harness = Self.subscribed()
    _ = harness.send(
      .subscribe(
        topic: "other", configuration: RealtimeChannelConfiguration(), waiter: harness.waiter(),
        snapshot: Self.noStreams))
    let w = harness.waiter()
    _ = harness.send(.removeChannel(topic: Self.topic, waiter: w))

    let effects = harness.send(.frame(Self.close(joinRef: "1")))

    #expect(!effects.contains(.scheduleIdleDisconnect(after: .seconds(50))))
    #expect(effects.last == .finishChannel(Self.topic))
    #expect(!harness.core.idleDisconnectPending)
  }

  @Test
  func removingTheLastChannelDisconnectsAtOnceWhenTheDelayIsZero() throws {
    var options = RealtimeCore.Options.test
    options.disconnectOnEmptyChannelsAfter = .zero
    var harness = CoreHarness.connected(options: options)
    let socket = try #require(harness.socket)
    let w1 = harness.waiter()
    let w2 = harness.waiter()
    _ = harness.send(Self.subscribe(w1))
    _ = harness.send(.frame(Self.reply(ref: "1")))
    _ = harness.send(.removeChannel(topic: Self.topic, waiter: w2))

    #expect(
      harness.send(.frame(Self.close(joinRef: "1"))) == [
        .resume(w2, .success),
        .publishChannelStatus(Self.topic, .unsubscribed),
        .cancel(.leaveTimeout(topic: Self.topic, ref: "2")),
        .finishChannel(Self.topic),
        .publishClientStatus(.disconnected(nil)),
        .cancelAllTasks,
        .closeSocket(socket, code: nil, reason: "Client disconnect"),
        .cancel(.heartbeat),
      ])
    #expect(!harness.core.idleDisconnectPending)
  }

  @Test
  func commandOnRemovedTopicFails() {
    var harness = Self.subscribed()
    _ = harness.send(.removeChannel(topic: Self.topic, waiter: harness.waiter()))
    _ = harness.send(.frame(Self.close(joinRef: "1")))
    let w = harness.waiter()

    #expect(
      harness.send(.push(topic: Self.topic, event: "x", payload: [:], waiter: w)) == [
        .resume(w, .failure(.notSubscribed))
      ])
    #expect(harness.send(.push(topic: Self.topic, event: "x", payload: [:], waiter: nil)) == [])
  }

  // MARK: Helpers

  static func subscribe(_ waiter: WaiterID) -> Event {
    .subscribe(
      topic: topic, configuration: RealtimeChannelConfiguration(), waiter: waiter,
      snapshot: noStreams)
  }

  /// A connected harness whose channel joined with ref `"1"`. It used waiter id 1.
  static func subscribed() -> CoreHarness {
    var harness = CoreHarness.connected()
    _ = harness.send(subscribe(harness.waiter()))
    _ = harness.send(.frame(reply(ref: "1")))
    return harness
  }

  static func join(ref: Ref) throws -> RealtimeMessage {
    let payload = RealtimeJoinPayload(
      config: RealtimeJoinConfig(
        RealtimeChannelConfiguration(), bindings: [], presenceEnabled: false),
      accessToken: nil, version: nil)
    return RealtimeMessage(
      joinRef: ref, ref: ref, topic: "realtime:\(topic)", event: "phx_join",
      payload: try JSONObject(payload))
  }

  static func reply(ref: Ref) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: ref, ref: ref, topic: "realtime:\(topic)", event: "phx_reply",
      payload: ["status": "ok", "response": [:]])
  }

  static func leave(joinRef: Ref, ref: Ref) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: joinRef, ref: ref, topic: "realtime:\(topic)", event: "phx_leave", payload: [:])
  }

  static func close(joinRef: Ref?) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: joinRef, ref: nil, topic: "realtime:\(topic)", event: "phx_close", payload: [:])
  }

  static func error(joinRef: Ref?) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: joinRef, ref: nil, topic: "realtime:\(topic)", event: "phx_error", payload: [:])
  }
}
