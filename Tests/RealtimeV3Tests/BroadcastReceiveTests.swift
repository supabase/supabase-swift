//
//  BroadcastReceiveTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import ConcurrencyExtras
import Foundation
import Testing

@testable import RealtimeV3

// MARK: - Test Helpers

private struct ChatMsg: Codable, Sendable, Equatable {
  let text: String
}

// MARK: - BroadcastReceiveTests

@Suite struct BroadcastReceiveTests {

  // MARK: - receivesTypedBroadcast

  /// Verifies that a broadcast frame with the correct inner event is decoded and yielded.
  @Test func receivesTypedBroadcast() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    server.autoReplyToJoins()
    try await channel.subscribe()

    // Register the typed stream BEFORE injecting the frame.
    let stream = await channel.broadcasts(of: ChatMsg.self, event: "chat")
    var iter = stream.makeAsyncIterator()

    // Inject a broadcast frame with inner event "chat".
    server.send(
      .text(
        #"["1",null,"room:1","broadcast",{"type":"broadcast","event":"chat","payload":{"text":"hi"}}]"#
      ))

    // Read first value — bounded by task timeout.
    let value = try await iter.next()
    #expect(value == ChatMsg(text: "hi"))
  }

  // MARK: - ignoresOtherEvents

  /// Injects an "other" event first, then a "chat" event. Only the "chat" event should
  /// be yielded to a broadcasts(of:event:"chat") stream.
  @Test func ignoresOtherEvents() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    server.autoReplyToJoins()
    try await channel.subscribe()

    // Register the typed stream BEFORE injecting any frames.
    let stream = await channel.broadcasts(of: ChatMsg.self, event: "chat")
    var iter = stream.makeAsyncIterator()

    // Inject "other" event — should be ignored by the "chat" stream.
    server.send(
      .text(
        #"["1",null,"room:1","broadcast",{"type":"broadcast","event":"other","payload":{"text":"ignored"}}]"#
      ))

    // Inject "chat" event — should be the FIRST thing yielded.
    server.send(
      .text(
        #"["2",null,"room:1","broadcast",{"type":"broadcast","event":"chat","payload":{"text":"hello"}}]"#
      ))

    // Only the "chat" message arrives; if "other" were yielded, it would arrive first.
    let value = try await iter.next()
    #expect(value == ChatMsg(text: "hello"))
  }

  // MARK: - leaveTerminatesBroadcastStreamWithChannelClosed

  /// Calling leave() causes the broadcasts stream to throw .channelClosed(.userRequested).
  @Test func leaveTerminatesBroadcastStreamWithChannelClosed() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    server.autoReplyToJoins()
    server.autoReplyToLeaves()

    try await channel.subscribe()

    // Register stream BEFORE calling leave().
    let stream = await channel.broadcasts(of: ChatMsg.self, event: "chat")

    // Collect results in a background task — looking for the thrown error.
    let receivedError = LockIsolated<RealtimeError?>(nil)
    let done = LockIsolated(false)
    let collectionTask = Task {
      do {
        for try await _ in stream {
          // No messages expected before leave.
        }
        // Stream ended without throwing — unexpected.
        done.withValue { $0 = true }
      } catch let error as RealtimeError {
        receivedError.withValue { $0 = error }
        done.withValue { $0 = true }
      } catch {
        done.withValue { $0 = true }
      }
    }

    // Leave the channel — this should terminate the stream with channelClosed.
    try await channel.leave()

    // Wait for collection task to finish (bounded).
    var waitIterations = 0
    while !done.value {
      try await Task.sleep(nanoseconds: 1_000_000)  // 1ms
      waitIterations += 1
      if waitIterations > 1000 {
        Issue.record("Broadcast stream was not finished after leave() within 1s")
        collectionTask.cancel()
        return
      }
    }
    collectionTask.cancel()

    // Verify the stream threw .channelClosed(.userRequested).
    let error = receivedError.value
    if case .channelClosed(let reason) = error {
      #expect(reason == .userRequested)
    } else {
      Issue.record("Expected .channelClosed(.userRequested), got \(String(describing: error))")
    }
  }
}
