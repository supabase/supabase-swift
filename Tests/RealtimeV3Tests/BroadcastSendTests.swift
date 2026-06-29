//
//  BroadcastSendTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import ConcurrencyExtras
import Foundation
import Testing

@testable import RealtimeV3

// MARK: - Test models

private struct ChatMsg: Encodable, Sendable {
  let text: String
}

// MARK: - BroadcastSendTests

@Suite struct BroadcastSendTests {

  // MARK: - sendBeforeSubscribeThrowsNotSubscribed

  /// A channel that has never been subscribed must throw `.notSubscribed` when broadcast is called.
  @Test func sendBeforeSubscribeThrowsNotSubscribed() async throws {
    let (transport, _) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    do {
      try await channel.broadcast(ChatMsg(text: "hi"), as: "chat")
      Issue.record("Expected .notSubscribed to be thrown")
    } catch {
      // broadcast(_:as:) uses typed throws(RealtimeError), so error IS a RealtimeError.
      if case .notSubscribed = error {
        // Expected — test passes.
      } else {
        Issue.record("Expected .notSubscribed, got \(error)")
      }
    }
  }

  // MARK: - subscribedBroadcastEmitsBinaryFrame

  /// After subscribing, broadcast() must emit a binary frame with kind byte 0x03.
  @Test func subscribedBroadcastEmitsBinaryFrame() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    server.autoReplyToJoins()
    try await channel.subscribe()

    // Collect frames the client sends in background.
    let sentFrames = LockIsolated<[TransportFrame]>([])
    let frameObserver = server.subscribeToClientFrames()
    let observerTask = Task {
      for await frame in frameObserver {
        sentFrames.withValue { $0.append(frame) }
      }
    }
    defer { observerTask.cancel() }

    try await channel.broadcast(ChatMsg(text: "hi"), as: "chat")

    // Allow a tick for frame to be observed.
    await Task.yield()

    // Verify at least one binary frame with kind byte 3 was sent.
    let frames = sentFrames.value
    let binaryFrames = frames.compactMap { frame -> Data? in
      if case .binary(let data) = frame { return data }
      return nil
    }

    let broadcastFrame = binaryFrames.first { data in
      !data.isEmpty && data[data.startIndex] == 3
    }
    #expect(broadcastFrame != nil, "Expected a binary broadcast frame (kind byte 3) to be sent")
  }

  // MARK: - ackModeAwaitsReply

  /// When broadcast.acknowledge == true, broadcast() waits for the server ack before returning.
  @Test func ackModeAwaitsReply() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(
      url: URL(string: "wss://x")!,
      apiKey: "k",
      transport: transport
    )
    let channel = await rt.channel("room:1") { opts in
      opts.broadcast.acknowledge = true
    }

    server.autoReplyToJoins()
    try await channel.subscribe()

    // Set up auto-reply for broadcast acks.
    server.autoReplyToBroadcasts()

    // This must return without timing out (the server will ack it).
    try await channel.broadcast(ChatMsg(text: "ack-test"), as: "chat")

    // If we reach here, the ack was received successfully.
    #expect(Bool(true))
  }

  // MARK: - dataOverloadEmitsBinaryFrame

  /// The Data overload sends a binary frame with kind byte 0x03.
  @Test func dataOverloadEmitsBinaryFrame() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:2")

    server.autoReplyToJoins()
    try await channel.subscribe()

    let sentFrames = LockIsolated<[TransportFrame]>([])
    let frameObserver = server.subscribeToClientFrames()
    let observerTask = Task {
      for await frame in frameObserver {
        sentFrames.withValue { $0.append(frame) }
      }
    }
    defer { observerTask.cancel() }

    let rawData = Data([0xDE, 0xAD, 0xBE, 0xEF])
    try await channel.broadcast(rawData, as: "raw")

    await Task.yield()

    let frames = sentFrames.value
    let binaryFrames = frames.compactMap { frame -> Data? in
      if case .binary(let data) = frame { return data }
      return nil
    }
    let broadcastFrame = binaryFrames.first { data in
      !data.isEmpty && data[data.startIndex] == 3
    }
    #expect(
      broadcastFrame != nil, "Expected a binary broadcast frame (kind byte 3) for Data overload")
  }
}
