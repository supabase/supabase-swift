//
//  RejoinTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import IssueReporting
import Testing

@testable import RealtimeV3

@Suite struct RejoinTests {

  // MARK: - Helpers

  /// Advance the TestClock in small steps, yielding to the cooperative thread pool between each
  /// advance, until `condition()` returns true or `maxAttempts` is reached.
  private func advanceUntil(
    clock: TestClock<Duration>,
    step: Duration,
    maxAttempts: Int = 200,
    condition: () async -> Bool
  ) async {
    for _ in 0..<maxAttempts {
      await Task.yield()
      await clock.advance(by: step)
      for _ in 0..<10 {
        await Task.yield()
      }
      if await condition() {
        return
      }
    }
  }

  // MARK: - rejoinsChannelAfterReconnect

  @Test func rejoinsChannelAfterReconnect() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let clock = TestClock()
    var config = Configuration.default
    config.clock = clock
    config.heartbeat = .seconds(25)
    config.reconnection = .exponentialBackoff(initial: .seconds(1), max: .seconds(30), jitter: 0)
    let rt = Realtime(
      url: URL(string: "wss://x")!,
      apiKey: "k",
      configuration: config,
      transport: transport
    )

    // Register a postgres insert subscription on the channel.
    let channel = await rt.channel("realtime:public:messages")
    _ = try await channel.inserts(schema: "public", table: "messages")

    // autoReplyToJoins replies to every phx_join across ALL reconnects.
    // It uses a broadcast subscriber so it survives the first connect.
    server.autoReplyToJoins(
      response: [
        "postgres_changes": .array([
          .object(["id": .integer(1)])
        ])
      ]
    )

    // Subscribe (first join).
    try await channel.subscribe()
    let stateAfterFirstJoin = await channel.channelState
    #expect(stateAfterFirstJoin == .joined)

    // Open a messages() stream BEFORE the reconnect — it must survive the gap.
    let messagesStream = await channel.messages()
    let messagesStreamEnded = LockIsolated(false)
    let messagesTask = Task {
      for await _ in messagesStream {
        // Consume frames; if the stream terminates this loop exits.
      }
      messagesStreamEnded.setValue(true)
    }
    defer { messagesTask.cancel() }

    // Track how many phx_join frames we observe.
    let joinCount = LockIsolated(0)
    // We use a broadcast subscriber so we see all joins across all connections.
    let clientFrames = server.subscribeToClientFrames()
    let joinCounterTask = Task.detached {
      for await frame in clientFrames {
        guard case .text(let text) = frame else { continue }
        guard text.contains("phx_join") else { continue }
        joinCount.withValue { $0 += 1 }
      }
    }
    defer { joinCounterTask.cancel() }

    // Give the counter task a moment to set up.
    await Task.yield()

    // Simulate server-initiated close.
    server.closeFromServer(code: 1006, reason: "abnormal")

    // Advance clock until we observe a re-join (joinCount >= 1 means a new phx_join was sent
    // after the counter was registered, i.e., the re-join after reconnect).
    await advanceUntil(clock: clock, step: .seconds(1)) {
      joinCount.value >= 1
    }

    #expect(joinCount.value >= 1, "Expected at least 1 re-join phx_join frame after reconnect")

    // Wait for the channel to complete its rejoin handshake (autoReplyToJoins sends a reply,
    // the channel processes it and transitions to .joined). Yield until joined or max tries.
    await advanceUntil(clock: clock, step: .milliseconds(10), maxAttempts: 100) {
      await channel.channelState == .joined
    }

    // The messages() stream must NOT have terminated during the reconnect gap.
    for _ in 0..<20 {
      await Task.yield()
    }
    #expect(!messagesStreamEnded.value, "messages() stream must survive reconnect gap")

    // Channel state should be .joined again after rejoin.
    let stateAfterRejoin = await channel.channelState
    #expect(stateAfterRejoin == .joined, "Channel must be .joined after rejoin")
  }

  // MARK: - rejoinCarriesPostgresRegistration

  @Test func rejoinCarriesPostgresRegistration() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let clock = TestClock()
    var config = Configuration.default
    config.clock = clock
    config.heartbeat = .seconds(25)
    config.reconnection = .exponentialBackoff(initial: .seconds(1), max: .seconds(30), jitter: 0)
    let rt = Realtime(
      url: URL(string: "wss://x")!,
      apiKey: "k",
      configuration: config,
      transport: transport
    )

    let channel = await rt.channel("realtime:public:items")
    _ = try await channel.inserts(schema: "public", table: "items")

    server.autoReplyToJoins(
      response: [
        "postgres_changes": .array([.object(["id": .integer(2)])])
      ]
    )

    try await channel.subscribe()

    // Collect the text of each phx_join frame.
    let joinFrames = LockIsolated<[String]>([])
    let clientFrames = server.subscribeToClientFrames()
    let frameTask = Task.detached {
      for await frame in clientFrames {
        guard case .text(let text) = frame else { continue }
        guard text.contains("phx_join") else { continue }
        joinFrames.withValue { $0.append(text) }
      }
    }
    defer { frameTask.cancel() }

    await Task.yield()

    server.closeFromServer(code: 1006, reason: "abnormal")

    await advanceUntil(clock: clock, step: .seconds(1)) {
      joinFrames.value.count >= 1
    }

    #expect(joinFrames.value.count >= 1, "Expected a re-join frame after reconnect")
    // The re-join frame must include the postgres_changes subscription.
    let rejoinText = joinFrames.value.last ?? ""
    #expect(
      rejoinText.contains("postgres_changes"),
      "Re-join frame must carry postgres_changes registration"
    )
    #expect(
      rejoinText.contains("items"),
      "Re-join frame must carry the table name"
    )
  }

  // MARK: - userLeftChannelNotRejoined

  @Test func userLeftChannelNotRejoined() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let clock = TestClock()
    var config = Configuration.default
    config.clock = clock
    config.heartbeat = .seconds(25)
    config.reconnection = .exponentialBackoff(initial: .seconds(1), max: .seconds(30), jitter: 0)
    let rt = Realtime(
      url: URL(string: "wss://x")!,
      apiKey: "k",
      configuration: config,
      transport: transport
    )

    // Create TWO channels: one we will leave, one we keep alive to trigger reconnect.
    let leftChannel = await rt.channel("realtime:public:left_table")
    let liveChannel = await rt.channel("realtime:public:live_table")

    server.autoReplyToJoins()
    server.autoReplyToLeaves()

    // Subscribe both channels.
    try await leftChannel.subscribe()
    try await liveChannel.subscribe()

    // Leave the first channel explicitly.
    try await leftChannel.leave()
    let stateAfterLeave = await leftChannel.channelState
    #expect(stateAfterLeave == .closed(.userRequested))

    // Track phx_join frames per topic after the disconnect.
    let leftTopicJoins = LockIsolated(0)
    let liveTopicJoins = LockIsolated(0)
    let clientFrames = server.subscribeToClientFrames()
    let frameTask = Task.detached {
      for await frame in clientFrames {
        guard case .text(let text) = frame else { continue }
        guard text.contains("phx_join") else { continue }
        if text.contains("left_table") {
          leftTopicJoins.withValue { $0 += 1 }
        }
        if text.contains("live_table") {
          liveTopicJoins.withValue { $0 += 1 }
        }
      }
    }
    defer { frameTask.cancel() }

    await Task.yield()

    // Trigger server-initiated close.
    server.closeFromServer(code: 1006, reason: "abnormal")

    // Advance until the live channel re-joins (proves reconnect happened).
    await advanceUntil(clock: clock, step: .seconds(1)) {
      liveTopicJoins.value >= 1
    }

    #expect(liveTopicJoins.value >= 1, "live_table channel must re-join after reconnect")
    #expect(leftTopicJoins.value == 0, "left_table channel must NOT re-join (user left)")
  }

  // MARK: - giveUpTerminatesChannelStreams

  @Test func giveUpTerminatesChannelStreams() async throws {
    let (transport, server) = InMemoryTransport.pair()
    var config = Configuration.default
    config.reconnection = .never
    let rt = Realtime(
      url: URL(string: "wss://x")!,
      apiKey: "k",
      configuration: config,
      transport: transport
    )

    let channel = await rt.channel("realtime:public:posts")
    server.autoReplyToJoins()
    try await channel.subscribe()

    // Open a broadcasts stream — it should throw .channelClosed(.transportFailure) on give-up.
    let broadcastsStream = await channel.broadcasts(of: String.self, event: "new")
    let broadcastError = LockIsolated<RealtimeError?>(nil)
    let broadcastTask = Task {
      do {
        for try await _ in broadcastsStream {}
      } catch let err as RealtimeError {
        broadcastError.setValue(err)
      } catch {}
    }
    defer { broadcastTask.cancel() }

    // Open a messages() stream — it should finish (no error).
    let messagesStream = await channel.messages()
    let messagesEnded = LockIsolated(false)
    let messagesTask = Task {
      for await _ in messagesStream {}
      messagesEnded.setValue(true)
    }
    defer { messagesTask.cancel() }

    // Simulate server close — with .never policy, give-up happens immediately.
    server.closeFromServer(code: 1006, reason: "abnormal")

    // Yield until streams terminate.
    for _ in 0..<200 {
      await Task.yield()
      if broadcastError.value != nil && messagesEnded.value { break }
    }

    // Broadcasts stream must throw .channelClosed(.transportFailure).
    if let err = broadcastError.value {
      if case .channelClosed(let reason) = err {
        #expect(reason == .transportFailure, "Expected .transportFailure close reason")
      } else {
        Issue.record("Expected .channelClosed(.transportFailure), got: \(err)")
      }
    } else {
      Issue.record("broadcasts stream did not throw on give-up")
    }

    // messages() stream must finish cleanly.
    #expect(messagesEnded.value, "messages() stream must finish cleanly on give-up")

    // Channel state must be .closed(.transportFailure).
    let finalState = await channel.channelState
    if case .closed(let reason) = finalState {
      #expect(reason == .transportFailure, "Channel state must be .closed(.transportFailure)")
    } else {
      Issue.record("Channel state must be .closed(.transportFailure), got: \(finalState)")
    }
  }
}
