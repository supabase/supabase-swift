//
//  BroadcastE2ETests.swift
//  RealtimeV3IntegrationTests
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation
import RealtimeV3
import Testing

// MARK: - Shared fixture

private struct ChatMsg: Codable, Sendable, Equatable {
  let text: String
}

/// IE-3: Broadcast e2e tests against a live local Supabase instance.
///
/// These tests require a running local Supabase stack:
///   cd Tests/RealtimeV3IntegrationTests/supabase && supabase start
///
/// They are automatically skipped when the instance is not reachable.
@Suite("IE-3 Broadcast", .requiresLocalSupabase)
struct BroadcastE2ETests {

  // MARK: - IE-3a: WS round-trip between two clients

  @Test("two WS clients on the same topic exchange a broadcast message")
  func broadcastRoundTripBetweenTwoClients() async throws {
    let rtA = IntegrationEnv.makeRealtime()
    let rtB = IntegrationEnv.makeRealtime()

    let channelA = await rtA.channel("room:e2e-broadcast")
    let channelB = await rtB.channel("room:e2e-broadcast")

    // Open the receive stream on B BEFORE subscribe so no message is missed.
    let receivedStream = await channelB.broadcasts(of: ChatMsg.self, event: "chat")

    // Subscribe both clients.
    try await channelA.subscribe()
    try await channelB.subscribe()

    // Wait for both channels to be joined before broadcasting.
    let stateA = await channelA.state
    let stateB = await channelB.state
    try await waitFor(stateA, timeout: .seconds(10), description: "channelA joined") {
      $0 == .joined
    }
    try await waitFor(stateB, timeout: .seconds(10), description: "channelB joined") {
      $0 == .joined
    }

    // A sends; B should receive.
    try await channelA.broadcast(ChatMsg(text: "hi"), as: "chat")

    // Collect the first element from B's stream within the timeout.
    var receivedMsg: ChatMsg?
    try await withThrowingTaskGroup(of: ChatMsg?.self) { group in
      group.addTask {
        for try await msg in receivedStream {
          return msg
        }
        return nil
      }
      group.addTask {
        try await Task.sleep(for: .seconds(10))
        throw TimeoutError(
          description: "B did not receive broadcast within timeout",
          timeout: .seconds(10)
        )
      }
      receivedMsg = try await group.next()!
      group.cancelAll()
    }

    #expect(receivedMsg == ChatMsg(text: "hi"))

    try await channelA.leave()
    try await channelB.leave()
    await rtA.disconnect()
    await rtB.disconnect()
  }

  // MARK: - IE-3b: HTTP broadcast received by WS subscriber

  // SDK GAP (tracked concern): `Channel.httpBroadcast` uses the SDK-internal full topic
  // string (e.g. "realtime:room:foo") in the HTTP broadcast request body. However, the
  // Realtime server's `/api/broadcast` endpoint expects the SHORT topic (without the
  // "realtime:" prefix) to match against WebSocket subscribers. Using the full topic
  // causes the server to accept the request (HTTP 202) but NOT deliver to subscribers.
  //
  // Workaround in this test: bypass `Channel.httpBroadcast` and call
  // `Realtime.httpBroadcastBatch` directly with the correct short topic. This lets us
  // verify that the delivery path works while documenting the SDK gap.

  @Test(
    "HTTP broadcast (via Realtime.httpBroadcastBatch with short topic) is delivered to a WS subscriber"
  )
  func httpBroadcastReceivedByWSSubscriber() async throws {
    let rtB = IntegrationEnv.makeRealtime()
    let channelB = await rtB.channel("room:e2e-http-broadcast")

    let receivedStream = await channelB.broadcasts(of: ChatMsg.self, event: "chat")

    try await channelB.subscribe()
    let stateB = await channelB.state
    try await waitFor(stateB, timeout: .seconds(10), description: "channelB joined for HTTP test") {
      $0 == .joined
    }

    // Use the service-role client with the SHORT topic (without "realtime:" prefix).
    // The Realtime HTTP broadcast API requires:
    //   1. A service-role Bearer token (anon key → HTTP 500)
    //   2. The short topic string (the "realtime:" prefix is stripped on the server side)
    let rtSender = IntegrationEnv.makeRealtimeWithServiceRole()
    let shortTopic = "room:e2e-http-broadcast"  // without "realtime:" prefix
    let msg = HttpBroadcastMessage(
      topic: shortTopic, event: "chat", payload: ChatMsg(text: "http-hello"))
    try await rtSender.httpBroadcastBatch([msg])

    // B should receive the message over its WS subscription.
    var receivedMsg: ChatMsg?
    try await withThrowingTaskGroup(of: ChatMsg?.self) { group in
      group.addTask {
        for try await msg in receivedStream {
          return msg
        }
        return nil
      }
      group.addTask {
        try await Task.sleep(for: .seconds(10))
        throw TimeoutError(
          description: "B did not receive HTTP broadcast within timeout",
          timeout: .seconds(10)
        )
      }
      receivedMsg = try await group.next()!
      group.cancelAll()
    }

    #expect(receivedMsg == ChatMsg(text: "http-hello"))

    try await channelB.leave()
    await rtB.disconnect()
  }

  // MARK: - IE-3c: broadcast with ack returns without timeout

  @Test("broadcast with acknowledge=true returns without timing out")
  func ackBroadcastReturns() async throws {
    let rt = IntegrationEnv.makeRealtime()
    let channel = await rt.channel("room:e2e-ack") {
      $0.broadcast.acknowledge = true
    }

    try await channel.subscribe()
    let state = await channel.state
    try await waitFor(state, timeout: .seconds(10), description: "ack channel joined") {
      $0 == .joined
    }

    // This should return cleanly (server acks broadcast pushes).
    try await channel.broadcast(ChatMsg(text: "ack-me"), as: "chat")

    try await channel.leave()
    await rt.disconnect()
  }
}
