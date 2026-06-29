//
//  ServerCloseTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import ConcurrencyExtras
import Foundation
import Testing

@testable import RealtimeV3

// MARK: - Server close / error event handling

@Suite struct ServerCloseTests {

  // MARK: - serverPhxCloseTerminatesChannel

  /// An unsolicited `phx_close` from the server must:
  ///  1. Transition the channel to `.closed(.serverClosed(...))`.
  ///  2. Terminate any open `broadcasts(of:)` stream with `.channelClosed(.serverClosed(...))`.
  @Test func serverPhxCloseTerminatesChannel() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    server.autoReplyToJoins()
    try await channel.subscribe()

    // Register a broadcast stream BEFORE injecting the close frame.
    let broadcastStream = await channel.broadcasts(of: String.self, event: "evt")

    // Collect the broadcast stream error in a background task.
    let streamError = LockIsolated<(any Error)?>(nil)
    let streamDone = LockIsolated(false)
    let collectTask = Task {
      do {
        for try await _ in broadcastStream { /* no messages expected */  }
        streamDone.withValue { $0 = true }
      } catch {
        streamError.withValue { $0 = error }
        streamDone.withValue { $0 = true }
      }
    }
    defer { collectTask.cancel() }

    // Inject an unsolicited phx_close for the channel topic.
    server.send(.text(#"["1",null,"room:1","phx_close",{}]"#))

    // Wait for the state to reach .closed — bounded loop.
    var stateIter = await channel.state.makeAsyncIterator()
    var reachedClosed = false
    var iterations = 0
    while let s = await stateIter.next() {
      if case .closed = s {
        reachedClosed = true
        break
      }
      iterations += 1
      if iterations > 30 { break }
    }

    #expect(reachedClosed, "Channel did not reach .closed after server phx_close")

    // Confirm it is specifically .closed(.serverClosed(...)).
    let finalState = await channel.channelState
    if case .closed(let reason) = finalState {
      if case .serverClosed = reason {
        // expected
      } else {
        Issue.record("Expected .serverClosed, got \(reason)")
      }
    } else {
      Issue.record("Expected .closed, got \(finalState)")
    }

    // Wait for the broadcast stream to finish (bounded).
    var waitIterations = 0
    while !streamDone.value {
      try await Task.sleep(nanoseconds: 1_000_000)  // 1ms
      waitIterations += 1
      if waitIterations > 500 { break }
    }

    // Verify the broadcast stream threw .channelClosed with serverClosed reason.
    let err = streamError.value
    if let realtimeErr = err as? RealtimeError {
      if case .channelClosed(let reason) = realtimeErr {
        if case .serverClosed = reason {
          // expected
        } else {
          Issue.record("Expected .channelClosed(.serverClosed), got .channelClosed(\(reason))")
        }
      } else {
        Issue.record("Expected .channelClosed, got \(realtimeErr)")
      }
    } else {
      Issue.record("Expected RealtimeError, got \(String(describing: err))")
    }
  }

  // MARK: - serverSystemAuthErrorClosesUnauthorized

  /// A `system` event with `status == "error"` and an auth-related message must close
  /// the channel with `.unauthorized`.
  @Test func serverSystemAuthErrorClosesUnauthorized() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    server.autoReplyToJoins()
    try await channel.subscribe()

    // Inject a non-postgres system error with "token" in the message.
    server.send(
      .text(
        #"[null,null,"room:1","system",{"status":"error","message":"Invalid JWT token"}]"#
      ))

    var stateIter = await channel.state.makeAsyncIterator()
    var reachedClosed = false
    var iterations = 0
    while let s = await stateIter.next() {
      if case .closed = s {
        reachedClosed = true
        break
      }
      iterations += 1
      if iterations > 30 { break }
    }

    #expect(reachedClosed, "Channel did not reach .closed after system auth error")

    let finalState = await channel.channelState
    if case .closed(let reason) = finalState {
      #expect(reason == .unauthorized, "Expected .unauthorized, got \(reason)")
    } else {
      Issue.record("Expected .closed, got \(finalState)")
    }
  }

  // MARK: - ownLeaveNotOverwrittenByTrailingPhxClose

  /// After `leave()` sets `.closed(.userRequested)`, a trailing `phx_close` frame from
  /// the server must NOT overwrite the reason to `.serverClosed`.
  @Test func ownLeaveNotOverwrittenByTrailingPhxClose() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    server.autoReplyToJoins()
    server.autoReplyToLeaves()

    try await channel.subscribe()

    // Leave the channel — transitions to .closed(.userRequested).
    try await channel.leave()

    // Confirm the channel is already .closed(.userRequested).
    let stateAfterLeave = await channel.channelState
    if case .closed(let reason) = stateAfterLeave {
      #expect(reason == .userRequested, "After leave(), expected .userRequested, got \(reason)")
    } else {
      Issue.record("After leave(), expected .closed, got \(stateAfterLeave)")
      return
    }

    // Inject a trailing phx_close from the server (simulating race between leave ACK and server close).
    server.send(.text(#"["1",null,"room:1","phx_close",{}]"#))

    // Yield briefly so the frame can be processed.
    await Task.yield()
    await Task.yield()

    // The reason must still be .userRequested, not overwritten to .serverClosed.
    let finalState = await channel.channelState
    if case .closed(let reason) = finalState {
      #expect(reason == .userRequested, "Trailing phx_close overwrote reason to \(reason)")
    } else {
      Issue.record("Expected .closed after trailing phx_close, got \(finalState)")
    }
  }

  // MARK: - serverPhxErrorTerminatesChannel

  /// A `phx_error` frame from the server closes the channel with `.serverClosed`.
  @Test func serverPhxErrorTerminatesChannel() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    server.autoReplyToJoins()
    try await channel.subscribe()

    server.send(.text(#"[null,null,"room:1","phx_error",{}]"#))

    var stateIter = await channel.state.makeAsyncIterator()
    var reachedClosed = false
    var iterations = 0
    while let s = await stateIter.next() {
      if case .closed = s {
        reachedClosed = true
        break
      }
      iterations += 1
      if iterations > 30 { break }
    }

    #expect(reachedClosed, "Channel did not reach .closed after phx_error")

    let finalState = await channel.channelState
    if case .closed(let reason) = finalState {
      if case .serverClosed = reason {
        // expected
      } else {
        Issue.record("Expected .serverClosed, got \(reason)")
      }
    } else {
      Issue.record("Expected .closed, got \(finalState)")
    }
  }
}

// MARK: - Encoder tests

@Suite struct ConfiguredEncoderTests {

  // MARK: - configuredEncoderUsedForBroadcast

  /// A custom `keyEncodingStrategy` on `Configuration.encoder` must be reflected in
  /// the broadcast payload bytes. We use `.convertToSnakeCase` which turns `myField`
  /// into `my_field` — unambiguous in the JSON.
  @Test func configuredEncoderUsedForBroadcast() async throws {
    struct Payload: Encodable, Sendable {
      let myField: String
    }

    let (transport, server) = InMemoryTransport.pair()

    var config = Configuration()
    config.encoder = {
      let enc = JSONEncoder()
      enc.keyEncodingStrategy = .convertToSnakeCase
      return enc
    }()

    let rt = Realtime(
      url: URL(string: "wss://x")!, apiKey: "k", configuration: config, transport: transport
    )
    let channel = await rt.channel("room:1")

    server.autoReplyToJoins()
    server.autoReplyToBroadcasts()
    try await channel.subscribe()

    // Observe frames the client sends.
    let sentFrames = LockIsolated<[Data]>([])
    let frameObserver = server.subscribeToClientFrames()
    let observerTask = Task {
      for await frame in frameObserver {
        if case .binary(let data) = frame {
          sentFrames.withValue { $0.append(data) }
        }
      }
    }
    defer { observerTask.cancel() }

    try await channel.broadcast(Payload(myField: "hello"), as: "test")

    // Allow a tick for the frame to be observed.
    await Task.yield()
    await Task.yield()

    // Find the broadcast frame and decode its JSON payload.
    let frames = sentFrames.value
    let broadcastData = frames.first { !$0.isEmpty && $0[$0.startIndex] == 3 }
    guard let data = broadcastData else {
      Issue.record("No binary broadcast frame found")
      return
    }

    // Parse the binary frame: [kind:1][joinRefLen:1][refLen:1][topicLen:1][eventLen:1][metaLen:1][encoding:1][fields...][json]
    let headerSize = 7
    guard data.count > headerSize else {
      Issue.record("Binary frame too short")
      return
    }
    let joinRefLen = Int(data[data.startIndex + 1])
    let refLen = Int(data[data.startIndex + 2])
    let topicLen = Int(data[data.startIndex + 3])
    let eventLen = Int(data[data.startIndex + 4])
    let metaLen = Int(data[data.startIndex + 5])

    let payloadOffset =
      data.startIndex + headerSize + joinRefLen + refLen + topicLen + eventLen + metaLen
    guard data.count > payloadOffset - data.startIndex else {
      Issue.record("Binary frame too short for payload")
      return
    }

    let payloadData = Data(data[payloadOffset...])
    // The outer payload is the broadcast envelope: {"type":"broadcast","event":"test","payload":{"my_field":"hello"}}
    if let payloadStr = String(data: payloadData, encoding: .utf8) {
      #expect(
        payloadStr.contains("my_field"),
        "Expected snake_case key 'my_field' in payload, got: \(payloadStr)"
      )
      #expect(
        !payloadStr.contains("myField"),
        "Expected no camelCase key 'myField' in payload, got: \(payloadStr)"
      )
    } else {
      Issue.record("Could not decode payload as UTF-8")
    }
  }
}

// MARK: - VSN connect tests

@Suite struct VsnConnectTests {

  // MARK: - vsnSentOnConnect

  /// After `connect()`, the transport must receive a URL with `vsn=2.0.0` query param.
  @Test func vsnSentOnConnect() async throws {
    let (transport, _) = InMemoryTransport.pair()
    let rt = Realtime(
      url: URL(string: "wss://proj.supabase.co/realtime/v1")!, apiKey: "k", transport: transport)
    try await rt.connect()
    let url = await transport.lastConnectURL
    #expect(
      url?.query?.contains("vsn=2.0.0") == true,
      "Expected vsn=2.0.0 in connect URL, got: \(url?.query ?? "(nil)")"
    )
  }

  // MARK: - vsnRespectsProtocolVersionConfig

  /// If `Configuration.protocolVersion` is set to `.v1`, the URL should contain `vsn=1.0.0`.
  @Test func vsnRespectsProtocolVersionConfig() async throws {
    let (transport, _) = InMemoryTransport.pair()

    var config = Configuration()
    config.protocolVersion = .v1

    let rt = Realtime(
      url: URL(string: "wss://proj.supabase.co/realtime/v1")!,
      apiKey: "k",
      configuration: config,
      transport: transport
    )
    try await rt.connect()
    let url = await transport.lastConnectURL
    #expect(
      url?.query?.contains("vsn=1.0.0") == true,
      "Expected vsn=1.0.0 in connect URL, got: \(url?.query ?? "(nil)")"
    )
  }
}
