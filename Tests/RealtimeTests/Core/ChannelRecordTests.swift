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
