//
//  ChannelTableTests.swift
//  RealtimeTests
//

import Foundation
import Helpers
import TestHelpers
import Testing

@testable import Realtime

/// ``ChannelTable/idsByWireTopic`` follows the records as channels are created, removed, and
/// closed by the server.
@Suite
struct ChannelTableTests {
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
      harness.core.channels.idsByWireTopic == ["realtime:room": [room], "realtime:lobby": [lobby]])
    #expect(harness.core.channels.idsByWireTopic == harness.core.channels.rebuiltIndex)
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
      harness.core.channels.idsByWireTopic == ["realtime:room": [room], "realtime:lobby": [lobby]])
    _ = harness.send(.timerFired(.leaveTimeout(channel: lobby, ref: "3")))
    #expect(harness.core.channels.idsByWireTopic == ["realtime:room": [room]])

    _ = harness.send(.removeChannel(channel: room, waiter: harness.waiter()))
    _ = harness.send(.timerFired(.leaveTimeout(channel: room, ref: "4")))
    #expect(harness.core.channels.isEmpty)
    #expect(harness.core.channels.idsByWireTopic.isEmpty)
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
    #expect(harness.core.channels.idsByWireTopic.isEmpty)
    #expect(harness.core.liveChannel(forWireTopic: "realtime:room") == nil)
  }

  /// The client hands out channel ids in creation order, so the index keeps them sorted even
  /// when a record arrives out of order.
  @Test
  func channelsOfATopicStayInCreationOrder() {
    var table = ChannelTable()
    let first = ChannelID(rawValue: 1)
    let second = ChannelID(rawValue: 2)
    let third = ChannelID(rawValue: 3)
    let record = ChannelRecord(topic: "room", configuration: RealtimeChannelConfiguration())

    table.setRecord(record, for: third)
    table.setRecord(record, for: first)
    table.setRecord(record, for: second)
    table.setRecord(record, for: second)

    #expect(table.idsByWireTopic == ["realtime:room": [first, second, third]])
    #expect(table.first(onWireTopic: "realtime:room") { _ in true } == first)

    table.setRecord(nil, for: first)
    table.setRecord(nil, for: first)
    #expect(table.idsByWireTopic == ["realtime:room": [second, third]])
    #expect(table.first(onWireTopic: "realtime:room") { _ in true } == second)
    #expect(table.idsByWireTopic == table.rebuiltIndex)
  }

  @Test
  func updateChangesOnlyAnExistingRecord() {
    var table = ChannelTable()
    let room = ChannelID(rawValue: 1)
    let missing = ChannelID(rawValue: 2)
    table.setRecord(
      ChannelRecord(topic: "room", configuration: RealtimeChannelConfiguration()), for: room)

    #expect(table.update(room) { $0.isRemoving = true } != nil)
    #expect(table.update(missing) { $0.isRemoving = true } == nil)

    #expect(table[room]?.isRemoving == true)
    #expect(table[missing] == nil)
    #expect(table.idsByWireTopic == ["realtime:room": [room]])
    #expect(table.first(onWireTopic: "realtime:room") { !$0.isRemoving } == nil)
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

extension ChannelTable {
  /// ``idsByWireTopic`` as the records say it should be.
  var rebuiltIndex: [String: [ChannelID]] {
    Dictionary(grouping: ids.sorted()) { self[$0]?.wireTopic ?? "" }
  }
}
