//
//  ChannelTests.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/25.
//

import ConcurrencyExtras
import Foundation
import Testing

@testable import _Realtime

@Suite struct ChannelTests {
  static let testURL = URL(string: "ws://localhost:4000/realtime/v1")!

  // Helper: auto-reply to phx_join and phx_leave with ok
  private func makeAutoReplyServer(_ server: InMemoryServer) -> Task<Void, Never> {
    Task {
      do {
        for try await frame in server.receivedFrames {
          guard case .text(let text) = frame,
            let msg = try? PhoenixSerializer.decodeText(text),
            msg.event == "phx_join" || msg.event == "phx_leave"
          else { continue }
          let reply = PhoenixMessage(
            joinRef: msg.joinRef, ref: msg.ref, topic: msg.topic,
            event: "phx_reply",
            payload: ["status": .string("ok"), "response": .object([:])]
          )
          if let replyText = try? PhoenixSerializer.encodeText(reply) {
            await server.send(.text(replyText))
          }
        }
      } catch {
        // stream ended
      }
    }
  }

  @Test func joinTransitionsToJoined() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let realtime = Realtime(url: Self.testURL, apiKey: .literal("key"), transport: transport)
    try await realtime.connect()

    let autoReply = makeAutoReplyServer(server)
    defer { autoReply.cancel() }

    let channel = await realtime.channel("room:1")
    try await channel.join()
    let state = await channel.currentState
    #expect(state == .joined)
  }

  @Test func sameTopicReturnsSameChannelActor() async throws {
    let (transport, _) = InMemoryTransport.pair()
    let realtime = Realtime(url: Self.testURL, apiKey: .literal("key"), transport: transport)

    let ch1 = await realtime.channel("room:42")
    let ch2 = await realtime.channel("room:42")
    #expect(ch1 === ch2)
  }

  @Test func firstCallWinsOnOptions() async throws {
    let (transport, _) = InMemoryTransport.pair()
    let realtime = Realtime(url: Self.testURL, apiKey: .literal("key"), transport: transport)

    let ch1 = await realtime.channel("room:1") { $0.isPrivate = true }
    let ch2 = await realtime.channel("room:1") { $0.isPrivate = false }
    let opts = await ch1.options
    #expect(opts.isPrivate == true)
    #expect(ch1 === ch2)
  }

  @Test(.timeLimit(.minutes(1)))
  func leaveFinishesActiveStreams() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let realtime = Realtime(url: Self.testURL, apiKey: .literal("key"), transport: transport)
    try await realtime.connect()

    let autoReply = makeAutoReplyServer(server)
    defer { autoReply.cancel() }

    let channel = await realtime.channel("room:1")
    try await channel.join()

    // Get a broadcast stream — it should close with channelClosed when leave() is called
    let broadcastStream = await channel.broadcasts()
    let caughtError = LockIsolated<RealtimeError?>(nil)

    let collectTask = Task {
      do {
        for try await _ in broadcastStream { /* drain */  }
      } catch let e as RealtimeError {
        caughtError.withValue { $0 = e }
      } catch {
        // unexpected error type
      }
    }

    try await channel.leave()
    await collectTask.value
    #expect(caughtError.value == .channelClosed(.userRequested))
  }
}
