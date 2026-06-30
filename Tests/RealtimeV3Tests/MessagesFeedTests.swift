//
//  MessagesFeedTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import ConcurrencyExtras
import Foundation
import Helpers
import Testing

@testable import RealtimeV3

@Suite struct MessagesFeedTests {

  // MARK: - fanOutToMultipleConsumers

  /// Two independent messages() streams each receive the same broadcast frame.
  @Test func fanOutToMultipleConsumers() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    server.autoReplyToJoins()
    try await channel.subscribe()

    // Register both streams BEFORE injecting the frame.
    let stream1 = await channel.messages()
    let stream2 = await channel.messages()

    // Inject a broadcast frame for the channel topic.
    server.send(
      .text(#"["1",null,"realtime:room:1","broadcast",{"event":"chat","payload":{"x":1}}]"#))

    // Each stream should yield exactly one message with event == .broadcast.
    var iter1 = stream1.makeAsyncIterator()
    var iter2 = stream2.makeAsyncIterator()

    let msg1 = await iter1.next()
    let msg2 = await iter2.next()

    #expect(msg1?.event == .broadcast)
    #expect(msg2?.event == .broadcast)
  }

  // MARK: - lateConsumerStillReceivesSubsequentFrames

  /// A stream created AFTER a frame was already consumed still receives subsequent frames.
  @Test func lateConsumerStillReceivesSubsequentFrames() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    server.autoReplyToJoins()
    try await channel.subscribe()

    // First consumer registered before frame A.
    let stream1 = await channel.messages()
    var iter1 = stream1.makeAsyncIterator()

    // Inject frame A — first consumer receives it.
    server.send(
      .text(#"["1",null,"realtime:room:1","broadcast",{"event":"frameA","payload":{}}]"#))
    let msgA = await iter1.next()
    #expect(msgA?.event == .broadcast)

    // Register second consumer AFTER frame A was already delivered.
    let stream2 = await channel.messages()
    var iter2 = stream2.makeAsyncIterator()

    // Inject frame B — second consumer should receive it.
    server.send(
      .text(#"["2",null,"realtime:room:1","broadcast",{"event":"frameB","payload":{}}]"#))
    let msgB = await iter2.next()
    #expect(msgB?.event == .broadcast)
  }

  // MARK: - leaveFinishesMessageStreams

  /// Calling leave() finishes all open messages() streams so for-await loops end.
  @Test func leaveFinishesMessageStreams() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    server.autoReplyToJoins()
    server.autoReplyToLeaves()

    try await channel.subscribe()

    let stream = await channel.messages()

    // Collect messages in a background task. The task should complete once leave() finishes
    // all streams. We use a bounded array to avoid hanging if finish never comes.
    let collected = LockIsolated<[PhoenixMessage]>([])
    let done = LockIsolated(false)
    let collectionTask = Task {
      for await msg in stream {
        collected.withValue { $0.append(msg) }
      }
      done.withValue { $0 = true }
    }

    // Inject one frame to confirm the stream is live.
    server.send(
      .text(#"["1",null,"realtime:room:1","broadcast",{"event":"alive","payload":{}}]"#))

    // Give the collection task a moment to consume the frame.
    var waitIterations = 0
    while collected.value.isEmpty {
      try await Task.sleep(nanoseconds: 1_000_000)  // 1ms
      waitIterations += 1
      if waitIterations > 1000 {
        Issue.record("First frame not received within 1s")
        collectionTask.cancel()
        return
      }
    }

    // Now leave — this should finish the stream.
    try await channel.leave()

    // Await the collection task to complete (stream finished).
    var finishIterations = 0
    while !done.value {
      try await Task.sleep(nanoseconds: 1_000_000)  // 1ms
      finishIterations += 1
      if finishIterations > 1000 {
        Issue.record("messages() stream was not finished after leave() within 1s")
        collectionTask.cancel()
        return
      }
    }

    // We received one frame and then the stream finished.
    #expect(collected.value.count == 1)
    #expect(collected.value.first?.event == .broadcast)
    #expect(done.value == true)

    collectionTask.cancel()
  }
}
