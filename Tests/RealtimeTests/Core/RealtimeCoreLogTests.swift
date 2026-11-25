//
//  RealtimeCoreLogTests.swift
//  RealtimeTests
//

import Foundation
import TestHelpers
import Testing

@testable import Realtime

/// The core's debug lines name states and events by case only: an associated
/// ``RealtimeError`` can hold a server's or a transport's text.
@Suite
struct RealtimeCoreLogTests {
  typealias Subscribe = RealtimeCoreSubscribeTests

  @Test
  func aRefusedJoinLogsNoServerReason() {
    let recorder = LogRecorder()
    var harness = CoreHarness.connected(logger: recorder.makeLogger())
    _ = harness.send(Subscribe.subscribe(harness.waiter(), channel: harness.channel()))

    _ = harness.send(
      .frame(Subscribe.reply(ref: "1", error: .joinError(reason: "UnknownErrorOnChannel: secret"))))

    #expect(recorder.entries.contains { $0.contains("Server refused the join") })
    #expect(recorder.entries.contains { $0.contains("joining → waitingToRetry") })
    #expect(!recorder.entries.contains { $0.contains("secret") })
  }

  @Test
  func aFailedConnectLogsNoTransportText() {
    let recorder = LogRecorder()
    var harness = CoreHarness(logger: recorder.makeLogger())
    _ = harness.send(Subscribe.subscribe(harness.waiter()))

    _ = harness.send(.socketOpenFailed(.transport("could not reach wss://x.co/?apikey=secret")))

    #expect(recorder.entries.contains { $0.contains("on socketOpenFailed") })
    #expect(!recorder.entries.contains { $0.contains("secret") })
  }
}
