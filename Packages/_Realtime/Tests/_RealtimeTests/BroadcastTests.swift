//
//  BroadcastTests.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/25.
//

import ConcurrencyExtras
import Foundation
import Testing

@testable import _Realtime

@Suite struct BroadcastTests {
  static let testURL = URL(string: "ws://localhost:4000/realtime/v1")!

  // MARK: - Helpers

  /// Returns a connected Realtime + InMemoryServer pair with an auto-reply task for phx_join/phx_leave.
  private func makeConnectedRealtime() async throws -> (
    realtime: Realtime,
    server: InMemoryServer,
    autoReplyTask: Task<Void, Never>
  ) {
    let (transport, server) = InMemoryTransport.pair()
    let realtime = Realtime(url: Self.testURL, apiKey: .literal("key"), transport: transport)
    try await realtime.connect()

    let autoReplyTask = Task {
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
    return (realtime, server, autoReplyTask)
  }

  // MARK: - Text broadcast delivery

  @Test func broadcastDeliveredToUntypedStream() async throws {
    let (realtime, server, autoReplyTask) = try await makeConnectedRealtime()
    defer { autoReplyTask.cancel() }

    let channel = await realtime.channel("room:1")
    let stream = await channel.broadcasts()
    let received = LockIsolated<[BroadcastMessage]>([])

    let collectTask = Task {
      do {
        for try await msg in stream {
          received.withValue { $0.append(msg) }
        }
      } catch {
        // stream finished
      }
    }
    defer { collectTask.cancel() }

    // Wait for auto-join to complete
    try await Task.sleep(for: .milliseconds(100))

    // Server pushes a broadcast
    let push = PhoenixMessage(
      joinRef: nil, ref: nil, topic: "room:1", event: "broadcast",
      payload: [
        "type": "broadcast",
        "event": .string("chat"),
        "payload": .object(["text": .string("hello")]),
      ]
    )
    await server.send(.text(try PhoenixSerializer.encodeText(push)))

    try await Task.sleep(for: .milliseconds(100))

    #expect(received.value.count == 1)
    #expect(received.value.first?.event == "chat")
    if case .object(let obj) = received.value.first?.payload {
      #expect(obj["text"] == .string("hello"))
    } else {
      Issue.record("Expected object payload")
    }
  }

  // MARK: - Fan-out to multiple subscribers

  @Test func broadcastFanoutToMultipleSubscribers() async throws {
    let (realtime, server, autoReplyTask) = try await makeConnectedRealtime()
    defer { autoReplyTask.cancel() }

    let channel = await realtime.channel("room:2")
    let count1 = LockIsolated(0)
    let count2 = LockIsolated(0)

    let s1 = await channel.broadcasts()
    let s2 = await channel.broadcasts()

    let t1 = Task {
      do {
        for try await _ in s1 { count1.withValue { $0 += 1 } }
      } catch { /* finished */  }
    }
    let t2 = Task {
      do {
        for try await _ in s2 { count2.withValue { $0 += 1 } }
      } catch { /* finished */  }
    }
    defer {
      t1.cancel()
      t2.cancel()
    }

    // Wait for joins to complete
    try await Task.sleep(for: .milliseconds(150))

    let push = PhoenixMessage(
      joinRef: nil, ref: nil, topic: "room:2", event: "broadcast",
      payload: [
        "type": "broadcast",
        "event": .string("ping"),
        "payload": .object([:]),
      ]
    )
    await server.send(.text(try PhoenixSerializer.encodeText(push)))

    try await Task.sleep(for: .milliseconds(100))

    #expect(count1.value == 1)
    #expect(count2.value == 1)
  }

  // MARK: - Typed broadcasts stream

  @Test func typedBroadcastsDecodesPayload() async throws {
    struct ChatMessage: Decodable, Sendable { let text: String }

    let (realtime, server, autoReplyTask) = try await makeConnectedRealtime()
    defer { autoReplyTask.cancel() }

    let channel = await realtime.channel("room:typed")
    let received = LockIsolated<[ChatMessage]>([])

    let stream = await channel.broadcasts(of: ChatMessage.self, event: "chat")
    let collectTask = Task {
      do {
        for try await msg in stream {
          received.withValue { $0.append(msg) }
        }
      } catch { /* finished */  }
    }
    defer { collectTask.cancel() }

    try await Task.sleep(for: .milliseconds(100))

    let push = PhoenixMessage(
      joinRef: nil, ref: nil, topic: "room:typed", event: "broadcast",
      payload: [
        "type": "broadcast",
        "event": .string("chat"),
        "payload": .object(["text": .string("world")]),
      ]
    )
    await server.send(.text(try PhoenixSerializer.encodeText(push)))

    // Different-event message should be filtered
    let otherPush = PhoenixMessage(
      joinRef: nil, ref: nil, topic: "room:typed", event: "broadcast",
      payload: [
        "type": "broadcast",
        "event": .string("other"),
        "payload": .object(["text": .string("ignored")]),
      ]
    )
    await server.send(.text(try PhoenixSerializer.encodeText(otherPush)))

    try await Task.sleep(for: .milliseconds(100))

    #expect(received.value.count == 1)
    #expect(received.value.first?.text == "world")
  }

  // MARK: - Send: not joined

  @Test func broadcastThrowsChannelNotJoinedIfNotJoined() async throws {
    let (transport, _) = InMemoryTransport.pair()
    let realtime = Realtime(url: Self.testURL, apiKey: .literal("key"), transport: transport)
    try await realtime.connect()
    let channel = await realtime.channel("room:3")

    struct Msg: Encodable, Sendable { let x: Int }
    do {
      try await channel.broadcast(Msg(x: 1), as: "event")
      Issue.record("Expected channelNotJoined error")
    } catch RealtimeError.channelNotJoined {
      // expected
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  // MARK: - Binary broadcast delivery

  @Test func binaryBroadcastDeliveredAsJSONPayload() async throws {
    let (realtime, server, autoReplyTask) = try await makeConnectedRealtime()
    defer { autoReplyTask.cancel() }

    let channel = await realtime.channel("room:binary")
    let received = LockIsolated<[BroadcastMessage]>([])
    let stream = await channel.broadcasts()
    let collectTask = Task {
      do {
        for try await msg in stream {
          received.withValue { $0.append(msg) }
        }
      } catch { /* finished */  }
    }
    defer { collectTask.cancel() }

    try await Task.sleep(for: .milliseconds(100))

    // Build a binary broadcast frame (server->client, type 0x04).
    // Layout: kind(1) | topicLen(1) | eventLen(1) | metaLen(1) | encoding(1) | topic | event | payload
    let topicBytes = Data("room:binary".utf8)
    let eventBytes = Data("update".utf8)
    let payloadDict: [String: JSONValue] = ["val": .int(42)]
    let payloadData = try JSONEncoder().encode(payloadDict)
    var frame = Data()
    frame.append(0x04)  // kind = serverBroadcast
    frame.append(UInt8(topicBytes.count))  // topicLen
    frame.append(UInt8(eventBytes.count))  // eventLen
    frame.append(0x00)  // metaLen
    frame.append(0x01)  // encoding = json
    frame.append(topicBytes)
    frame.append(eventBytes)
    // meta (0 bytes)
    frame.append(payloadData)

    await server.send(.binary(frame))

    try await Task.sleep(for: .milliseconds(100))

    #expect(received.value.count == 1)
    #expect(received.value.first?.event == "update")
    if case .object(let obj) = received.value.first?.payload {
      #expect(obj["val"] == .int(42))
    } else {
      Issue.record("Expected object payload")
    }
  }

  // MARK: - Stream finishes on leave

  @Test(.timeLimit(.minutes(1)))
  func broadcastStreamFinishesOnLeave() async throws {
    let (realtime, _, autoReplyTask) = try await makeConnectedRealtime()
    defer { autoReplyTask.cancel() }

    let channel = await realtime.channel("room:leave")
    let stream = await channel.broadcasts()
    let caughtError = LockIsolated<RealtimeError?>(nil)

    let collectTask = Task {
      do {
        for try await _ in stream { /* drain */  }
      } catch let e as RealtimeError {
        caughtError.withValue { $0 = e }
      }
    }

    // Wait for join
    try await Task.sleep(for: .milliseconds(100))

    try await channel.leave()
    _ = await collectTask.result

    #expect(caughtError.value == .channelClosed(.userRequested))
  }
}
