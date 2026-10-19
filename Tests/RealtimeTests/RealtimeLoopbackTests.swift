//
//  RealtimeLoopbackTests.swift
//  RealtimeTests
//
//  Created by Guilherme Souza on 19/10/26.
//

import ConcurrencyExtras
import Foundation
import Helpers
import Testing

@testable import Realtime

#if canImport(Network) && !os(Linux)
  import Network

  /// End-to-end: the production client, the real `URLSessionWebSocket` transport, and a
  /// loopback WebSocket server that speaks just enough Phoenix to join and broadcast.
  @Suite(.serialized, .timeLimit(.minutes(1)))
  struct RealtimeLoopbackTests {
    @Test
    func connectsJoinsAndRoundTripsABroadcast() async throws {
      let server = try LoopbackWebSocketServer()
      let port = try server.start()
      defer { server.stop() }
      let joins = script(server)

      let client = makeClient(port: port)
      try await client.connect()
      #expect(client.statusSnapshot == .connected)

      let channel = await client.channel("room") {
        $0.broadcast.receiveOwnBroadcasts = true
      }
      let pings = await channel.broadcasts(event: "ping")
      try await channel.subscribe()
      #expect(channel.statusSnapshot == .subscribed)
      #expect(joins.value == 1)

      await channel.broadcast(event: "ping", message: ["n": 1])
      let received = try await withTimeout(.seconds(10)) {
        await pings.first { _ in true }
      }
      #expect(received?["event"] == "ping")
      #expect(received?["payload"]?.objectValue?["n"] == 1)

      await client.disconnect()
      #expect(client.statusSnapshot == .disconnected)
    }

    @Test
    func reconnectsAndRejoinsAfterTheServerCloses() async throws {
      let server = try LoopbackWebSocketServer()
      let port = try server.start()
      defer { server.stop() }
      let joins = script(server)

      let client = makeClient(port: port)
      let channel = await client.channel("room")
      try await channel.subscribe()
      #expect(joins.value == 1)

      var clientStatuses = client.statusChanges.makeAsyncIterator()
      var channelStatuses = channel.statusChanges.makeAsyncIterator()
      #expect(await clientStatuses.next() == .connected)
      #expect(await channelStatuses.next() == .subscribed)

      server.close(code: .protocolCode(.goingAway), reason: "restart")

      #expect(await clientStatuses.next() == .connecting)
      #expect(await clientStatuses.next() == .connected)
      #expect(await channelStatuses.next() == .unsubscribed)
      #expect(await channelStatuses.next() == .subscribing)
      #expect(await channelStatuses.next() == .subscribed)
      #expect(joins.value == 2)

      await client.disconnect()
    }

    // MARK: - Helpers

    private func makeClient(port: UInt16) -> RealtimeClient {
      RealtimeClient(
        url: URL(string: "http://127.0.0.1:\(port)")!,
        options: RealtimeClientOptions(
          heartbeatInterval: .seconds(30),
          reconnectDelay: .milliseconds(100),
          timeout: .seconds(10),
          handleAppLifecycle: false
        )
      )
    }

    /// Scripts the server: confirms joins, acknowledges heartbeats and echoes broadcasts back
    /// to the client. Returns the number of joins received.
    private func script(_ server: LoopbackWebSocketServer) -> LockIsolated<Int> {
      let joins = LockIsolated(0)
      server.onMessage = { data in
        let serializer = RealtimeSerializer()
        func send(_ reply: RealtimeMessageV2) {
          if let text = try? serializer.encodeText(reply) {
            server.send(text: text)
          }
        }

        if let text = String(data: data, encoding: .utf8),
          let message = try? serializer.decodeText(text)
        {
          switch message.event {
          case "phx_join":
            joins.withValue { $0 += 1 }
            send(
              RealtimeMessageV2(
                joinRef: message.joinRef, ref: message.ref, topic: message.topic,
                event: "phx_reply",
                payload: ["status": "ok", "response": ["postgres_changes": []]]
              )
            )
          case "heartbeat":
            send(
              RealtimeMessageV2(
                joinRef: nil, ref: message.ref, topic: "phoenix", event: "phx_reply",
                payload: ["status": "ok", "response": [:]]
              )
            )
          case "broadcast":
            send(
              RealtimeMessageV2(
                joinRef: nil, ref: nil, topic: message.topic, event: "broadcast",
                payload: message.payload
              )
            )
          default:
            break
          }
        } else if let push = Self.parseBroadcastPush(data) {
          send(
            RealtimeMessageV2(
              joinRef: nil, ref: nil, topic: push.topic, event: "broadcast",
              payload: [
                "type": "broadcast", "event": .string(push.event), "payload": .object(push.payload),
              ]
            )
          )
        }
      }
      return joins
    }

    /// Parses a client→server broadcast push with a JSON payload (binary kind 0x03). The
    /// production serializer only decodes the server→client kind, so the server side lives here.
    ///
    /// ```
    /// [kind:1][joinRef_len:1][ref_len:1][topic_len:1][event_len:1][meta_len:1][encoding:1]
    /// [joinRef][ref][topic][event][metadata][payload]
    /// ```
    private static func parseBroadcastPush(_ data: Data) -> (
      topic: String, event: String, payload: JSONObject
    )? {
      let header = Array(data.prefix(7))
      guard header.count == 7, header[0] == RealtimeSerializer.BinaryKind.userBroadcastPush.rawValue
      else {
        return nil
      }
      var index = data.startIndex + 7
      func field(_ length: UInt8) -> String {
        let end = index + Int(length)
        defer { index = end }
        return String(decoding: data[index..<end], as: UTF8.self)
      }
      _ = field(header[1])
      _ = field(header[2])
      let topic = field(header[3])
      let event = field(header[4])
      _ = field(header[5])
      guard let payload = try? JSONDecoder().decode(JSONObject.self, from: data[index...]) else {
        return nil
      }
      return (topic, event, payload)
    }
  }
#endif
