//
//  RealtimeCorePushTests.swift
//  RealtimeTests
//

import Foundation
import Helpers
import TestHelpers
import Testing

@testable import Realtime

/// The pushes of ``RealtimeCore``: broadcasts, presence `track` and `untrack`, their replies,
/// and their timeouts.
@Suite
struct RealtimeCorePushTests {
  typealias Event = RealtimeCore.Event
  typealias Effect = RealtimeCore.Effect

  static let topic = "room"
  static let wireTopic = "realtime:room"
  static let noStreams = JoinSnapshot(bindings: [], presenceEnabled: false)
  static let track: JSONObject = [
    "type": "presence", "event": "track", "payload": ["name": "alice"],
  ]
  static let cursor = BroadcastPushPayload.json(["x": 1])

  @Test
  func pushOnSubscribedSendsWithJoinRef() {
    var harness = Self.subscribed()
    let w = harness.waiter()

    #expect(
      harness.send(.push(topic: Self.topic, event: "presence", payload: Self.track, waiter: w))
        == [
          .send(Self.message(ref: "2", event: "presence", payload: Self.track)),
          .schedule(.pushTimeout(topic: Self.topic, ref: "2"), after: .seconds(10)),
        ])
    #expect(harness.core.channels[Self.topic]?.pendingPushes == ["2": w])

    // Without a waiter the push is fire-and-forget.
    #expect(
      harness.send(.push(topic: Self.topic, event: "presence", payload: Self.track, waiter: nil))
        == [.send(Self.message(ref: "3", event: "presence", payload: Self.track))])
    #expect(harness.core.channels[Self.topic]?.pendingPushes == ["2": w])
  }

  @Test
  func broadcastResolvesAfterTheSendWithoutAcknowledge() {
    var harness = Self.subscribed()
    let w = harness.waiter()

    #expect(
      harness.send(.broadcast(topic: Self.topic, event: "cursor", payload: Self.cursor, waiter: w))
        == [
          .sendBroadcast(
            joinRef: "1", ref: "2", topic: Self.wireTopic, event: "cursor", payload: Self.cursor),
          .resume(w, .success),
        ])
    #expect(harness.core.channels[Self.topic]?.pendingPushes.isEmpty == true)
  }

  @Test
  func pushNotSubscribedFailsNotSubscribed() {
    var harness = CoreHarness.connected()
    _ = harness.send(Self.subscribe(harness.waiter()))
    let broadcaster = harness.waiter()
    let other = harness.waiter()

    // The join is still in flight.
    #expect(
      harness.send(
        .broadcast(topic: Self.topic, event: "cursor", payload: Self.cursor, waiter: broadcaster))
        == [.resume(broadcaster, .failure(.notSubscribed))])
    #expect(
      harness.send(
        .broadcast(topic: "other", event: "cursor", payload: Self.cursor, waiter: other))
        == [.resume(other, .failure(.notSubscribed))])
  }

  @Test
  func trackBeforeSubscribedFailsNotSubscribed() {
    var harness = CoreHarness.connected()
    _ = harness.send(Self.subscribe(harness.waiter()))
    let tracker = harness.waiter()

    #expect(
      harness.send(
        .push(topic: Self.topic, event: "presence", payload: Self.track, waiter: tracker))
        == [.resume(tracker, .failure(.notSubscribed))])

    // Nothing was kept: the join's confirmation sends no presence frame.
    let confirmed = harness.send(.frame(Self.reply(ref: "1")))
    #expect(!confirmed.contains { Self.isUserPush($0) })
    #expect(harness.core.channels[Self.topic]?.pendingPushes.isEmpty == true)
  }

  @Test
  func noSendWhileDisconnected() {
    var harness = Self.subscribed()
    _ = harness.send(.socketFailed(.heartbeatTimeout))
    #expect(harness.core.channels[Self.topic]?.phase == .waitingForSocket(attempt: 1))
    let broadcaster = harness.waiter()
    let tracker = harness.waiter()

    #expect(
      harness.send(
        .broadcast(topic: Self.topic, event: "cursor", payload: Self.cursor, waiter: broadcaster))
        == [.resume(broadcaster, .failure(.notSubscribed))])
    #expect(
      harness.send(
        .push(topic: Self.topic, event: "presence", payload: Self.track, waiter: tracker))
        == [.resume(tracker, .failure(.notSubscribed))])
    #expect(
      harness.send(.push(topic: Self.topic, event: "presence", payload: Self.track, waiter: nil))
        == [])

    // The next socket carries only the rejoin.
    _ = harness.send(.retryTimerFired)
    let reconnected = harness.send(.socketOpened(FakeWebSocket.fakes().0))
    #expect(
      reconnected.contains { if case .send(let m) = $0 { m.event == "phx_join" } else { false } })
    #expect(!reconnected.contains { Self.isUserPush($0) })
  }

  @Test
  func ackPushResolvesOnOkReply() {
    var harness = Self.subscribed(configuration: Self.acknowledged)
    let w = harness.waiter()

    #expect(
      harness.send(.broadcast(topic: Self.topic, event: "cursor", payload: Self.cursor, waiter: w))
        == [
          .sendBroadcast(
            joinRef: "1", ref: "2", topic: Self.wireTopic, event: "cursor", payload: Self.cursor),
          .schedule(.pushTimeout(topic: Self.topic, ref: "2"), after: .seconds(10)),
        ])

    #expect(
      harness.send(.frame(Self.reply(ref: "2"))) == [
        .resume(w, .success),
        .cancel(.pushTimeout(topic: Self.topic, ref: "2")),
      ])
    #expect(harness.core.channels[Self.topic]?.pendingPushes.isEmpty == true)
    // The push is settled, so its timer is stale.
    #expect(harness.send(.timerFired(.pushTimeout(topic: Self.topic, ref: "2"))) == [])
  }

  @Test(arguments: [
    ("payload_size_exceeded", RealtimeError.Kind.payloadTooLarge),
    ("RealtimeDisabledForTenant: Realtime is disabled", RealtimeError.Kind.server),
  ])
  func ackPushFailsWithServerReason(reason: String, kind: RealtimeError.Kind) throws {
    var harness = Self.subscribed(configuration: Self.acknowledged)
    let w = harness.waiter()
    _ = harness.send(
      .broadcast(topic: Self.topic, event: "cursor", payload: Self.cursor, waiter: w))

    let effects = harness.send(
      .frame(Self.reply(ref: "2", status: "error", response: ["reason": .string(reason)])))

    #expect(
      effects == [
        .resume(w, .failure(.ackError(reason: reason))),
        .cancel(.pushTimeout(topic: Self.topic, ref: "2")),
      ])
    guard case .resume(_, .failure(let error))? = effects.first else {
      Issue.record("Expected a failed push, got \(effects)")
      return
    }
    #expect(error.kind == kind)
  }

  @Test
  func pushTimeoutFails() {
    var harness = Self.subscribed()
    let w = harness.waiter()
    _ = harness.send(.push(topic: Self.topic, event: "presence", payload: Self.track, waiter: w))

    #expect(harness.send(.timerFired(.pushTimeout(topic: Self.topic, ref: "9"))) == [])
    #expect(
      harness.send(.timerFired(.pushTimeout(topic: Self.topic, ref: "2"))) == [
        .resume(w, .failure(.pushTimeout))
      ])
    #expect(harness.core.channels[Self.topic]?.pendingPushes.isEmpty == true)
    // A late reply finds nothing to settle.
    #expect(harness.send(.frame(Self.reply(ref: "2"))) == [])
    #expect(harness.core.channels[Self.topic]?.phase == .subscribed(joinRef: "1"))
  }

  @Test
  func replyForUnknownRefIsDropped() {
    var harness = Self.subscribed()
    let w = harness.waiter()
    _ = harness.send(.push(topic: Self.topic, event: "presence", payload: Self.track, waiter: w))

    #expect(harness.send(.frame(Self.reply(ref: "9"))) == [])
    #expect(harness.send(.frame(Self.reply(ref: "9", status: "error"))) == [])
    #expect(harness.core.channels[Self.topic]?.pendingPushes == ["2": w])
    #expect(harness.core.channels[Self.topic]?.phase == .subscribed(joinRef: "1"))
  }

  @Test
  func replyWithoutRefOrStatusIsDropped() {
    var harness = Self.subscribed()
    let w = harness.waiter()
    _ = harness.send(.push(topic: Self.topic, event: "presence", payload: Self.track, waiter: w))
    let wireTopic = RealtimeChannel.wireTopic(for: Self.topic)

    let withoutRef = RealtimeMessage(
      joinRef: "1", ref: nil, topic: wireTopic, event: ChannelEvent.reply,
      payload: ["status": "ok"])
    let withoutStatus = RealtimeMessage(
      joinRef: "1", ref: "2", topic: wireTopic, event: ChannelEvent.reply, payload: [:])

    #expect(harness.send(.frame(withoutRef)) == [])
    #expect(harness.send(.frame(withoutStatus)) == [])
    #expect(harness.core.channels[Self.topic]?.pendingPushes == ["2": w])
    #expect(harness.core.channels[Self.topic]?.phase == .subscribed(joinRef: "1"))
  }

  @Test
  func fatalJoinErrorFailsPendingPushes() {
    var harness = Self.subscribed()
    let w = harness.waiter()
    _ = harness.send(.push(topic: Self.topic, event: "presence", payload: Self.track, waiter: w))
    // A new binding rejoins: leave with ref "3", join with ref "4". The push still waits.
    let messages = PostgresJoinConfig(event: .insert, schema: "public", table: "messages")
    _ = harness.send(
      .bindingsChanged(
        topic: Self.topic, snapshot: JoinSnapshot(bindings: [messages], presenceEnabled: false)))
    #expect(
      harness.core.channels[Self.topic]?.phase == .joining(ref: "4", attempt: 1, stage: .reply))

    let denied = RealtimeError.joinError(
      reason: "Unauthorized: You do not have permissions to read from this Channel topic: room")
    #expect(
      harness.send(
        .frame(
          Self.reply(ref: "4", status: "error", response: ["reason": .string(denied.message)])))
        == [
          .resume(w, .failure(.notSubscribed)),
          .cancel(.pushTimeout(topic: Self.topic, ref: "2")),
          .publishChannelStatus(Self.topic, .failed(denied)),
          .cancel(.joinTimeout(topic: Self.topic, ref: "4")),
        ])
    #expect(harness.core.channels[Self.topic]?.pendingPushes.isEmpty == true)
  }

  @Test
  func stalePushTimeoutAfterSocketDropDoesNothing() {
    var harness = Self.subscribed()
    let w = harness.waiter()
    _ = harness.send(.push(topic: Self.topic, event: "presence", payload: Self.track, waiter: w))

    let dropped = harness.send(.socketFailed(.heartbeatTimeout))
    #expect(dropped.contains(.resume(w, .failure(.notConnected))))
    #expect(dropped.contains(.cancel(.pushTimeout(topic: Self.topic, ref: "2"))))

    #expect(harness.send(.timerFired(.pushTimeout(topic: Self.topic, ref: "2"))) == [])
  }

  @Test
  func stalePushTimeoutAfterRemoveDoesNothing() {
    var harness = Self.subscribed()
    let w = harness.waiter()
    _ = harness.send(.push(topic: Self.topic, event: "presence", payload: Self.track, waiter: w))

    let removed = harness.send(.removeChannel(topic: Self.topic, waiter: harness.waiter()))
    #expect(
      Array(removed.prefix(2)) == [
        .resume(w, .failure(.channelRemoved)),
        .cancel(.pushTimeout(topic: Self.topic, ref: "2")),
      ])

    #expect(harness.send(.timerFired(.pushTimeout(topic: Self.topic, ref: "2"))) == [])
    _ = harness.send(.frame(Self.close(joinRef: "1")))
    #expect(harness.core.channels[Self.topic] == nil)
    #expect(harness.send(.timerFired(.pushTimeout(topic: Self.topic, ref: "2"))) == [])
  }

  // MARK: Helpers

  static var acknowledged: RealtimeChannelConfiguration {
    var configuration = RealtimeChannelConfiguration()
    configuration.broadcast.acknowledge = true
    return configuration
  }

  static func subscribe(
    _ waiter: WaiterID,
    configuration: RealtimeChannelConfiguration = RealtimeChannelConfiguration()
  ) -> Event {
    .subscribe(
      topic: topic, configuration: configuration, waiter: waiter, snapshot: noStreams)
  }

  /// A connected harness whose channel joined with ref `"1"`. It used waiter id 1.
  static func subscribed(
    configuration: RealtimeChannelConfiguration = RealtimeChannelConfiguration()
  ) -> CoreHarness {
    var harness = CoreHarness.connected()
    _ = harness.send(subscribe(harness.waiter(), configuration: configuration))
    _ = harness.send(.frame(reply(ref: "1")))
    return harness
  }

  static func message(ref: Ref, event: String, payload: JSONObject) -> RealtimeMessage {
    RealtimeMessage(joinRef: "1", ref: ref, topic: wireTopic, event: event, payload: payload)
  }

  static func reply(
    ref: Ref, status: String = "ok", response: JSONObject = [:]
  ) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: "1", ref: ref, topic: wireTopic, event: "phx_reply",
      payload: ["status": .string(status), "response": .object(response)])
  }

  static func close(joinRef: Ref?) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: joinRef, ref: nil, topic: wireTopic, event: "phx_close", payload: [:])
  }

  /// Whether `effect` writes a broadcast or a presence frame.
  static func isUserPush(_ effect: Effect) -> Bool {
    switch effect {
    case .sendBroadcast:
      true
    case .send(let message):
      message.event == "presence"
    default:
      false
    }
  }
}
