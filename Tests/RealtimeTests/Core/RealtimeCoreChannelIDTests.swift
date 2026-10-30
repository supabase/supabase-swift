//
//  RealtimeCoreChannelIDTests.swift
//  RealtimeTests
//

import Foundation
import Helpers
import TestHelpers
import Testing

@testable import Realtime

/// How ``RealtimeCore`` keeps several channels of one topic apart: a new channel joins while an
/// old one leaves, and inbound frames reach the channel their `join_ref` names.
@Suite
struct RealtimeCoreChannelIDTests {
  typealias Event = RealtimeCore.Event
  typealias Effect = RealtimeCore.Effect

  static let topic = "room"
  static let noStreams = JoinSnapshot(bindings: [], presenceEnabled: false)

  /// A connected core where `old` joined `"room"` with ref `"1"` and `removeChannel` sent its
  /// `phx_leave` (ref `"2"`). Then `new` subscribed to `"room"`, with join ref `"3"`.
  let harness: CoreHarness
  let old: ChannelID
  let new: ChannelID
  let removeWaiter: WaiterID
  let newWaiter: WaiterID
  let newJoinRef: Ref = "3"
  /// The effects of the subscribe of `new`.
  let effects: [Effect]

  init() {
    var harness = CoreHarness.connected()
    old = harness.channel()
    _ = harness.send(Self.subscribe(old, waiter: harness.waiter()))
    _ = harness.send(.frame(Self.joinReply(topic: Self.topic, ref: "1", status: .ok)))
    removeWaiter = harness.waiter()
    _ = harness.send(.removeChannel(channel: old, waiter: removeWaiter))
    new = harness.channel()
    newWaiter = harness.waiter()
    effects = harness.send(Self.subscribe(new, waiter: newWaiter))
    self.harness = harness
  }

  @Test
  func newChannelJoinsWhileTheOldOneLeaves() {
    #expect(effects.contains { if case .send(let m) = $0 { m.event == "phx_join" } else { false } })
    #expect(!effects.contains(.resume(newWaiter, .failure(.channelRemoved))))
    #expect(harness.core.channels[old]?.isRemoving == true)
    #expect(harness.core.channels[new]?.topic == "room")
  }

  @Test
  func closeForTheOldJoinLeavesTheNewChannelAlone() {
    var harness = self.harness
    let effects = harness.send(.frame(Self.close(topic: Self.topic, joinRef: "1")))

    #expect(effects.contains(.finishChannel(old)))
    #expect(effects.contains(.resume(removeWaiter, .success)))
    #expect(!effects.contains { $0.mentions(new) })
    #expect(
      harness.core.channels[new]?.phase.status.isSame(as: .subscribing(attempt: 1)) == true)
  }

  @Test
  func replyToTheNewJoinSubscribesOnlyTheNewChannel() {
    var harness = self.harness
    let effects = harness.send(
      .frame(Self.joinReply(topic: Self.topic, ref: newJoinRef, status: .ok)))

    #expect(effects.contains(.publishChannelStatus(new, .subscribed)))
    #expect(effects.contains(.resume(newWaiter, .success)))
    #expect(!effects.contains { $0.mentions(old) })
  }

  @Test
  func broadcastGoesToTheLiveChannelOnly() {
    var harness = self.harness
    let effects = harness.send(.frame(Self.broadcast(topic: Self.topic, event: "msg")))

    #expect(effects.count == 1)
    #expect(effects.first?.deliveredTo == new)
  }

  @Test
  func closeWithoutJoinRefGoesToTheLiveChannel() {
    var harness = self.harness
    let effects = harness.send(.frame(Self.close(topic: Self.topic, joinRef: nil)))

    #expect(effects.contains(.finishChannel(new)))
    #expect(effects.contains(.resume(newWaiter, .failure(.channelClosedByServer))))
    #expect(!effects.contains { $0.mentions(old) })
    #expect(!effects.contains(.resume(removeWaiter, .success)))
    #expect(harness.core.channels[old]?.phase == .leaving(joinRef: "1", leaveRef: "2"))
  }

  @Test
  func commandsForAnUnknownChannelResolveAtOnce() {
    var harness = self.harness
    let unknown = harness.channel()
    let unsubscribe = harness.waiter()
    let remove = harness.waiter()
    let push = harness.waiter()

    let effects =
      harness.send(.unsubscribe(channel: unknown, waiter: unsubscribe))
      + harness.send(.removeChannel(channel: unknown, waiter: remove))
      + harness.send(.push(channel: unknown, event: "x", payload: [:], waiter: push))

    #expect(effects.contains(.resume(unsubscribe, .success)))
    #expect(effects.contains(.resume(remove, .success)))
    #expect(effects.contains(.resume(push, .failure(.notSubscribed))))
    #expect(!effects.contains { if case .send = $0 { true } else { false } })
  }

  // MARK: Helpers

  static func subscribe(_ channel: ChannelID, waiter: WaiterID) -> Event {
    .subscribe(
      channel: channel, topic: topic, configuration: RealtimeChannelConfiguration(),
      waiter: waiter, snapshot: noStreams)
  }

  static func joinReply(topic: String, ref: Ref, status: PushStatus) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: ref, ref: ref, topic: "realtime:\(topic)", event: "phx_reply",
      payload: ["status": .string(status.rawValue), "response": [:]])
  }

  static func close(topic: String, joinRef: Ref?) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: joinRef, ref: nil, topic: "realtime:\(topic)", event: "phx_close", payload: [:])
  }

  static func broadcast(topic: String, event: String) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: nil, ref: nil, topic: "realtime:\(topic)", event: "broadcast",
      payload: ["type": "broadcast", "event": .string(event), "payload": [:]])
  }
}

extension RealtimeCore.Effect {
  /// Whether the effect names `id`: a status, a delivery, a finish, or a timer of that channel.
  fileprivate func mentions(_ id: ChannelID) -> Bool {
    switch self {
    case .publishChannelStatus(let channel, _), .deliver(let channel, _),
      .finishChannel(let channel):
      channel == id
    case .schedule(let timer, _), .cancel(let timer):
      timer.channel == id
    default:
      false
    }
  }

  /// The channel a `.deliver` effect delivers to.
  fileprivate var deliveredTo: ChannelID? {
    if case .deliver(let channel, _) = self { channel } else { nil }
  }
}

extension TimerID {
  /// The channel the timer belongs to, or `nil` for a client timer.
  fileprivate var channel: ChannelID? {
    switch self {
    case .heartbeat, .tokenRefresh:
      nil
    case .joinTimeout(let channel, _), .rejoin(let channel), .postgresTimeout(let channel, _),
      .leaveTimeout(let channel, _), .pushTimeout(let channel, _):
      channel
    }
  }
}
