//
//  RealtimeCoreTopicIndexTests.swift
//  RealtimeTests
//

import Foundation
import Helpers
import TestHelpers
import Testing

@testable import Realtime

/// ``RealtimeCore/channelsByWireTopic`` follows the records as channels are created, removed,
/// and closed by the server.
@Suite
struct RealtimeCoreTopicIndexTests {
  static let noStreams = JoinSnapshot(bindings: [], presenceEnabled: false)

  @Test
  func subscribeAddsTheChannelToItsTopic() {
    var harness = CoreHarness.connected()
    let room = harness.channel()
    let lobby = harness.channel()

    _ = harness.send(Self.subscribe(room, topic: "room", waiter: harness.waiter()))
    _ = harness.send(Self.subscribe(lobby, topic: "lobby", waiter: harness.waiter()))
    _ = harness.send(Self.subscribe(room, topic: "room", waiter: harness.waiter()))

    #expect(
      harness.core.channelsByWireTopic == ["realtime:room": [room], "realtime:lobby": [lobby]])
    #expect(harness.core.channelsByWireTopic == harness.core.rebuiltTopicIndex)
  }

  @Test
  func removeChannelDropsItFromItsTopic() {
    var harness = CoreHarness.connected()
    let room = harness.channel()
    let lobby = harness.channel()
    _ = harness.send(Self.subscribe(room, topic: "room", waiter: harness.waiter()))
    _ = harness.send(Self.subscribe(lobby, topic: "lobby", waiter: harness.waiter()))
    _ = harness.send(.frame(Self.joinReply(topic: "room", ref: "1")))
    _ = harness.send(.frame(Self.joinReply(topic: "lobby", ref: "2")))

    // The record stays until the leave ends.
    _ = harness.send(.removeChannel(channel: lobby, waiter: harness.waiter()))
    #expect(
      harness.core.channelsByWireTopic == ["realtime:room": [room], "realtime:lobby": [lobby]])
    _ = harness.send(.timerFired(.leaveTimeout(channel: lobby, ref: "3")))
    #expect(harness.core.channelsByWireTopic == ["realtime:room": [room]])

    _ = harness.send(.removeChannel(channel: room, waiter: harness.waiter()))
    _ = harness.send(.timerFired(.leaveTimeout(channel: room, ref: "4")))
    #expect(harness.core.channels.isEmpty)
    #expect(harness.core.channelsByWireTopic.isEmpty)
  }

  @Test
  func serverCloseDropsTheChannelFromItsTopic() {
    var harness = CoreHarness.connected()
    let room = harness.channel()
    _ = harness.send(Self.subscribe(room, topic: "room", waiter: harness.waiter()))
    _ = harness.send(.frame(Self.joinReply(topic: "room", ref: "1")))

    let effects = harness.send(
      .frame(
        RealtimeMessage(
          joinRef: "1", ref: nil, topic: "realtime:room", event: "phx_close", payload: [:])))

    #expect(effects.contains(.finishChannel(room)))
    #expect(harness.core.channelsByWireTopic.isEmpty)
    #expect(harness.core.liveChannel(forWireTopic: "realtime:room") == nil)
  }

  /// The client hands out channel ids in creation order, so the index keeps them sorted even
  /// when a record arrives out of order.
  @Test
  func channelsOfATopicStayInCreationOrder() {
    var core = RealtimeCore(options: .test, logger: .silent, initialToken: nil)
    let first = ChannelID(rawValue: 1)
    let second = ChannelID(rawValue: 2)
    let third = ChannelID(rawValue: 3)
    let record = ChannelRecord(topic: "room", configuration: RealtimeChannelConfiguration())

    core.setRecord(record, for: third)
    core.setRecord(record, for: first)
    core.setRecord(record, for: second)
    core.setRecord(record, for: second)

    #expect(core.channelsByWireTopic == ["realtime:room": [first, second, third]])
    #expect(core.liveChannel(forWireTopic: "realtime:room") == first)

    core.setRecord(nil, for: first)
    core.setRecord(nil, for: first)
    #expect(core.channelsByWireTopic == ["realtime:room": [second, third]])
    #expect(core.liveChannel(forWireTopic: "realtime:room") == second)
  }

  // MARK: Helpers

  static func subscribe(_ channel: ChannelID, topic: String, waiter: WaiterID)
    -> RealtimeCore.Event
  {
    .subscribe(
      channel: channel, topic: topic, configuration: RealtimeChannelConfiguration(),
      waiter: waiter, snapshot: noStreams)
  }

  static func joinReply(topic: String, ref: Ref) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: ref, ref: ref, topic: "realtime:\(topic)", event: "phx_reply",
      payload: ["status": "ok", "response": [:]])
  }
}

extension RealtimeCore {
  /// ``channelsByWireTopic`` as the records say it should be.
  var rebuiltTopicIndex: [String: [ChannelID]] {
    Dictionary(grouping: channels.keys.sorted()) { channels[$0]?.wireTopic ?? "" }
  }
}
