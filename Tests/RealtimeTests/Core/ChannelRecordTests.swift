//
//  ChannelRecordTests.swift
//  RealtimeTests
//

import Testing

@testable import Realtime

@Suite
struct ChannelRecordTests {
  typealias Phase = ChannelRecord.Phase

  static let timedOut = RealtimeError(kind: .timeout, message: "join timed out")

  @Test
  func phaseStatusIsThePublicStatus() {
    let rows: [(Phase, RealtimeChannelStatus)] = [
      (.unsubscribed, .unsubscribed),
      (.waitingForSocket(attempt: 1), .subscribing(attempt: 1)),
      (.refreshingToken(attempt: 2), .subscribing(attempt: 2)),
      (.joining(ref: "1", attempt: 3, stage: .reply), .subscribing(attempt: 3)),
      (.joining(ref: "1", attempt: 3, stage: .postgres), .subscribing(attempt: 3)),
      (
        .waitingToRetry(attempt: 2, retryIn: .seconds(2), lastError: Self.timedOut),
        .resubscribing(attempt: 2, retryIn: .seconds(2), lastError: Self.timedOut)
      ),
      (.subscribed(joinRef: "1"), .subscribed),
      (.leaving(joinRef: "1", leaveRef: "2"), .unsubscribing),
      (.failed(Self.timedOut), .failed(Self.timedOut)),
    ]

    for (phase, status) in rows {
      #expect(phase.status.isSame(as: status), "status of \(phase)")
    }
  }

  @Test
  func newRecordIsUnsubscribed() {
    let record = ChannelRecord(topic: "room", configuration: RealtimeChannelConfiguration())

    #expect(record.topic == "room")
    #expect(record.phase == .unsubscribed)
    #expect(!record.hasBeenSubscribed)
  }

  @Test(arguments: [
    (Phase.unsubscribed, true),
    (.failed(Self.timedOut), true),
    (.leaving(joinRef: "1", leaveRef: "2"), true),
    (.waitingForSocket(attempt: 1), false),
    (.refreshingToken(attempt: 1), false),
    (.joining(ref: "1", attempt: 1, stage: .reply), false),
    (.waitingToRetry(attempt: 1, retryIn: .seconds(1), lastError: Self.timedOut), false),
    (.subscribed(joinRef: "1"), false),
  ])
  func aChannelWithPresenceOffAcceptsAPresenceStreamOnlyBeforeItJoins(
    phase: Phase, accepts: Bool
  ) {
    var record = ChannelRecord(topic: "room", configuration: RealtimeChannelConfiguration())
    record.phase = phase

    #expect(record.acceptsPresenceStream == accepts)
  }

  @Test(arguments: [
    Phase.waitingForSocket(attempt: 1),
    .refreshingToken(attempt: 1),
    .joining(ref: "1", attempt: 1, stage: .reply),
    .waitingToRetry(attempt: 1, retryIn: .seconds(1), lastError: Self.timedOut),
    .subscribed(joinRef: "1"),
  ])
  func aSubscriptionWithPresenceOnAcceptsAPresenceStream(phase: Phase) {
    var configuration = RealtimeChannelConfiguration()
    configuration.presence.enabled = true
    var record = ChannelRecord(topic: "room", configuration: configuration)
    record.phase = phase

    #expect(record.acceptsPresenceStream)
  }

  @Test
  func aTrackCountsOnlyWhileItsJoinIsLive() {
    var record = ChannelRecord(topic: "room", configuration: RealtimeChannelConfiguration())
    record.hasTrackedSinceJoin = true

    record.phase = .subscribed(joinRef: "1")
    #expect(record.acceptsPresenceStream)
    record.phase = .waitingToRetry(attempt: 1, retryIn: .seconds(1), lastError: Self.timedOut)
    #expect(!record.acceptsPresenceStream)
  }

  @Test
  func aLeaveWithASubscribeQueuedUsesTheQueuedSubscription() {
    var record = ChannelRecord(topic: "room", configuration: RealtimeChannelConfiguration())
    record.phase = .leaving(joinRef: "1", leaveRef: "2")
    record.subscribeWaiters = [WaiterID(rawValue: 1)]

    #expect(!record.acceptsPresenceStream)
    record.snapshot.presenceEnabled = true
    #expect(record.acceptsPresenceStream)
  }

  @Test
  func phasesCompareErrorsByFailure() {
    #expect(
      Phase.failed(Self.timedOut)
        == .failed(RealtimeError(kind: .timeout, message: "join timed out")))
    #expect(Phase.failed(Self.timedOut) != .failed(.heartbeatTimeout))
    #expect(
      Phase.joining(ref: "1", attempt: 1, stage: .reply)
        != .joining(ref: "1", attempt: 1, stage: .postgres))
  }
}
