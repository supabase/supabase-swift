//
//  RealtimeStreamTests.swift
//  Realtime
//
//  Created by Guilherme Souza on 08/10/26.
//

import ConcurrencyExtras
import Foundation
import TestHelpers
import Testing

@testable import Realtime

@Suite(.timeLimit(.minutes(1)))
struct RealtimeStreamTests {
  let engine = RealtimeEngine(
    configuration: RealtimeEngineConfiguration(url: URL(string: "ws://fake")!),
    transport: FakeRealtimeServer().transport)
  let topic = "realtime:room"

  init() {
    engine.withState { [topic] in $0.install(topic, owner: testOwner, config: RealtimeJoinConfig())
    }
  }

  private func message(_ event: String) -> ChannelInbound {
    .message(RealtimeMessageV2(joinRef: nil, ref: nil, topic: topic, event: event, payload: [:]))
  }

  private func events(_ stream: RealtimeStream<String>) -> (
    LockIsolated<[String]>, Task<Void, Never>
  ) {
    let events = LockIsolated([String]())
    let task = Task { for await event in stream { events.withValue { $0.append(event) } } }
    return (events, task)
  }

  private static func eventName(_ inbound: ChannelInbound) -> String? {
    guard case .message(let message) = inbound else { return nil }
    return message.event
  }

  @Test
  func aStreamRegisteredBeforeAYieldReceivesIt() async {
    let stream = RealtimeStream(engine.inbound(topic), transform: Self.eventName)
    engine.yield(message("a"), to: topic)
    engine.finishInbound(topic)

    var received: [String] = []
    for await event in stream { received.append(event) }
    #expect(received == ["a"])
  }

  @Test
  func twoStreamsEachReceiveAMessageOnce() async {
    let (first, firstTask) = events(
      RealtimeStream(engine.inbound(topic), transform: Self.eventName))
    let (second, secondTask) = events(
      RealtimeStream(engine.inbound(topic), transform: Self.eventName))
    defer {
      firstTask.cancel()
      secondTask.cancel()
    }
    #expect(engine.listenerCount(topic) == 2)

    engine.yield(message("a"), to: topic)

    #expect(await waitUntil { first.value == ["a"] && second.value == ["a"] })
    try? await Task.sleep(nanoseconds: 50_000_000)
    #expect(first.value == ["a"])
    #expect(second.value == ["a"])
  }

  @Test
  func cancellingIterationRemovesTheListener() async {
    let (_, task) = events(RealtimeStream(engine.inbound(topic), transform: Self.eventName))
    #expect(engine.listenerCount(topic) == 1)

    task.cancel()

    #expect(await waitUntil { engine.listenerCount(topic) == 0 })
  }

  @Test
  func finishingTheTopicEndsTheStreamAndRemovesItsListeners() async {
    let stream = engine.inbound(topic)

    engine.finishInbound(topic)
    for await _ in stream {}

    #expect(engine.listenerCount(topic) == 0)
  }

  @Test
  func aNilTransformSkipsTheElement() async {
    let stream = RealtimeStream(engine.inbound(topic)) { inbound -> String? in
      guard let name = Self.eventName(inbound), name != "skip" else { return nil }
      return name
    }
    engine.yield(message("skip"), to: topic)
    engine.yield(.resubscribed, to: topic)
    engine.yield(message("keep"), to: topic)
    engine.finishInbound(topic)

    var received: [String] = []
    for await event in stream { received.append(event) }
    #expect(received == ["keep"])
  }

  @Test
  func anIdentityStreamPassesEveryElement() async {
    let (base, continuation) = AsyncStream<Int>.makeStream()
    continuation.yield(1)
    continuation.yield(2)
    continuation.finish()

    var received: [Int] = []
    for await value in RealtimeStream(base) { received.append(value) }
    #expect(received == [1, 2])
  }
}

extension RealtimeEngine {
  func yield(_ value: ChannelInbound, to topic: String) {
    withState { $0.yield(value, to: topic) }
  }

  func finishInbound(_ topic: String) {
    withState { $0.finishInbound(topic) }
  }
}
