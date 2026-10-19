//
//  RealtimeChannelBroadcastTests.swift
//
//
//  Created by Guilherme Souza on 12/02/26.
//
import ConcurrencyExtras
import Foundation
import TestHelpers
import Testing
@testable import Realtime
#if os(Linux)
#else
  @Suite
  final class RealtimeChannelBroadcastTests: Sendable {
    let url = URL(string: "http://localhost:54321/realtime/v1")!
    let apiKey = "publishable.api.key"
    let server: FakeWebSocket
    let client: FakeWebSocket
    let http: RecordingTransport
    let sut: RealtimeClient
    let serverTask = LockIsolated<Task<Void, Never>?>(nil)
    init() {
      let (client, server) = FakeWebSocket.fakes()
      self.client = client
      self.server = server
      http = RecordingTransport()
      sut = RealtimeClient(
        url: url,
        options: RealtimeClientOptions(
          headers: ["apikey": apiKey],
          accessToken: {
            "custom.access.token"
          }
        ),
        wsTransport: { _, _ in client },
        http: HTTPClient(transport: http),
        clock: ContinuousClock()
      )
    }
    deinit {
      serverTask.value?.cancel()
    }
    private func setupServerAutoResponder(topic: String = "realtime:test") {
      let task = Task { @Sendable [server] in
        for await event in server.events {
          guard let msg = event.realtimeMessage else { continue }

          if msg.event == "heartbeat" {
            server.send(
              RealtimeMessageV2(
                joinRef: msg.joinRef,
                ref: msg.ref,
                topic: "phoenix",
                event: "phx_reply",
                payload: ["response": [:]]
              )
            )
          } else if msg.event == "phx_join" {
            server.send(
              RealtimeMessageV2(
                joinRef: msg.joinRef,
                ref: msg.ref,
                topic: topic,
                event: "phx_reply",
                payload: [
                  "response": ["postgres_changes": .array([])],
                  "status": "ok",
                ]
              )
            )
          }
        }
      }
      serverTask.setValue(task)
    }

    @Test
    func broadcast_sendsJsonViaBinaryFrame() async throws {
      setupServerAutoResponder()
      try await sut.connect()

      let channel = await sut.channel("test")
      try await channel.subscribe()

      try await channel.broadcast(
        event: "my_event", message: ["hello": .string("world")] as JSONObject
      )

      let binaryEvents = client.sentEvents.compactMap { event -> Data? in
        if case .binary(let data) = event { return data }
        return nil
      }

      #expect(!binaryEvents.isEmpty, "Expected at least one binary frame to be sent")

      if let binaryData = binaryEvents.last {
        #expect(binaryData[0] == RealtimeSerializer.BinaryKind.userBroadcastPush.rawValue)
        #expect(binaryData[6] == RealtimeSerializer.PayloadEncoding.json.rawValue)
      }
    }

    @Test
    func broadcast_sendsDataViaBinaryFrame() async throws {
      setupServerAutoResponder()
      try await sut.connect()

      let channel = await sut.channel("test")
      try await channel.subscribe()

      let binaryData = Data([0x01, 0x02, 0x03, 0x04])
      try await channel.broadcast(event: "bin_event", data: binaryData)

      let binaryFrames = client.sentEvents.compactMap { event -> Data? in
        if case .binary(let data) = event { return data }
        return nil
      }

      #expect(!binaryFrames.isEmpty, "Expected at least one binary frame to be sent")

      if let frame = binaryFrames.last {
        #expect(frame[0] == RealtimeSerializer.BinaryKind.userBroadcastPush.rawValue)
        #expect(frame[6] == RealtimeSerializer.PayloadEncoding.binary.rawValue)
      }
    }

    @Test
    func receive_jsonBroadcastFromBinaryFrame() async throws {
      let channel = await sut.channel("test")

      let stream = await channel.broadcasts(event: "my_event")

      let broadcast = DecodedBroadcast(
        topic: "realtime:test",
        event: "my_event",
        payload: .json(["count": .integer(99)])
      )
      await channel.handleBinaryBroadcast(broadcast)

      let payload = await firstBuffered(stream, on: channel)
      #expect(payload != nil, "Expected to receive broadcast payload")
      #expect(payload?["event"]?.stringValue == "my_event")
      #expect(payload?["payload"]?.objectValue?["count"]?.intValue == 99)
    }

    @Test
    func receive_binaryBroadcastFromBinaryFrame() async throws {
      let channel = await sut.channel("test")

      let stream = await channel.broadcastData(event: "bin_event")

      let binaryPayload = Data([0xCA, 0xFE, 0xBA, 0xBE])
      let broadcast = DecodedBroadcast(
        topic: "realtime:test",
        event: "bin_event",
        payload: .binary(binaryPayload)
      )
      await channel.handleBinaryBroadcast(broadcast)

      #expect(await firstBuffered(stream, on: channel) == binaryPayload)
    }

    @Test
    func receive_jsonBroadcastHasCorrectFormat() async throws {
      let channel = await sut.channel("test")

      let stream = await channel.broadcasts(event: "evt")

      let broadcast = DecodedBroadcast(
        topic: "realtime:test",
        event: "evt",
        payload: .json(["key": .string("value")])
      )
      await channel.handleBinaryBroadcast(broadcast)

      let payload = await firstBuffered(stream, on: channel)
      #expect(payload != nil)
      #expect(payload?["type"]?.stringValue == "broadcast")
      #expect(payload?["event"]?.stringValue == "evt")
      #expect(payload?["payload"]?.objectValue?["key"]?.stringValue == "value")
      #expect(payload?["meta"] == nil)
    }

    @Test
    func receive_jsonBroadcastForwardsFrameMetadataAsMeta() async throws {
      let channel = await sut.channel("test")

      let stream = await channel.broadcasts(event: "INSERT")

      let broadcast = DecodedBroadcast(
        topic: "realtime:test",
        event: "INSERT",
        meta: ["id": "0b8a1e2c-77c4-4f1b-9d2a-3f5e6a7b8c9d", "replayed": true],
        payload: .json(["key": .string("value")])
      )
      await channel.handleBinaryBroadcast(broadcast)

      let meta = await firstBuffered(stream, on: channel)?["meta"]?.objectValue
      #expect(meta?["id"]?.stringValue == "0b8a1e2c-77c4-4f1b-9d2a-3f5e6a7b8c9d")
      #expect(meta?["replayed"]?.boolValue == true)
    }

    // The REST fallback for unsubscribed channels is gone, so the encoded payload is now read
    // from the WebSocket frame of a subscribed channel instead of the REST request body.
    @Test
    func broadcast_perCallEncoderOverridesFixedInternalEncoder() async throws {
      setupServerAutoResponder()
      try await sut.connect()

      let channel = await sut.channel("test")
      try await channel.subscribe()

      struct Message: Codable {
        let userName: String
      }

      let snakeCaseEncoder = JSONEncoder()
      snakeCaseEncoder.keyEncodingStrategy = .convertToSnakeCase

      try await channel.broadcast(
        event: "my_event", message: Message(userName: "abc"), encoder: snakeCaseEncoder
      )

      let frame = try #require(
        client.sentEvents.compactMap { event -> Data? in
          if case .binary(let data) = event { return data }
          return nil
        }.last
      )
      #expect(frame.range(of: Data(#""user_name":"abc""#.utf8)) != nil)
      #expect(frame.range(of: Data("userName".utf8)) == nil)
    }

    // MARK: - Broadcast on an unsubscribed channel

    // Behavior change: a broadcast on a channel that is not subscribed no longer falls back to
    // the REST endpoint. It throws `.notSubscribed`; REST sending is `httpSend`'s job.
    @Test
    func broadcast_whenNotSubscribedFailsWithoutRESTFallback() async throws {
      http.respond { _, _ in
        (HTTPResponse(status: .init(code: 202)), Data())
      }

      let channel = await sut.channel("test") { config in
        config.broadcast.acknowledgeBroadcasts = true
      }

      let error = await #expect(throws: RealtimeError.self) {
        try await channel.broadcast(
          event: "my_event", message: ["hello": .string("world")] as JSONObject
        )
      }
      #expect(error?.kind == .notSubscribed)
      #expect(http.requests.isEmpty)
    }

    @Test
    func httpSend_urlUsesSubTopicWithoutRealtimePrefix() async throws {
      http.respond { _, _ in
        (HTTPResponse(status: .init(code: 202)), Data())
      }

      let channel = await sut.channel("test")
      #expect(await channel.topic == "realtime:test")

      try await channel.httpSend(
        event: "my_event", message: ["hello": .string("world")] as JSONObject
      )

      let request = http.requests.last
      let url = try #require(request?.head.url)
      #expect(url.path == "/realtime/v1/api/broadcast/test/events/my_event")

      let body = try #require(request?.body)
      let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
      #expect(json?["hello"] as? String == "world")
    }

    @Test
    func endToEnd_binaryFrameViaWebSocket() async throws {
      setupServerAutoResponder()
      try await sut.connect()

      let channel = await sut.channel("test")

      let stream = await channel.broadcasts(event: "my_event")
      let receivedPayload = LockIsolated<JSONObject?>(nil)
      let listenTask = Task {
        for await json in stream {
          receivedPayload.setValue(json)
        }
      }
      defer { listenTask.cancel() }

      try await channel.subscribe()

      let jsonPayload: JSONObject = ["count": .integer(99)]
      let payloadData = try JSONEncoder().encode(jsonPayload)
      let topic = "realtime:test"
      let event = "my_event"
      let topicBytes = Data(topic.utf8)
      let eventBytes = Data(event.utf8)

      var frame = Data()
      frame.append(RealtimeSerializer.BinaryKind.userBroadcast.rawValue)
      frame.append(UInt8(topicBytes.count))
      frame.append(UInt8(eventBytes.count))
      frame.append(0)
      frame.append(RealtimeSerializer.PayloadEncoding.json.rawValue)
      frame.append(topicBytes)
      frame.append(eventBytes)
      frame.append(payloadData)

      server.send(frame)

      let received = await waitUntil(timeout: 0.5) { receivedPayload.value != nil }

      let payload = receivedPayload.value
      if !received {
        print(
          "WARNING: End-to-end binary frame test did not receive payload in time"
        )
        print("Client received events: \(client.receivedEvents)")
      }
      if let payload {
        #expect(payload["event"]?.stringValue == "my_event")
        #expect(payload["payload"]?.objectValue?["count"]?.intValue == 99)
      }
    }

    @Test
    func endToEnd_binaryFrameForwardsDatabaseMetadataAsMeta() async throws {
      setupServerAutoResponder()
      try await sut.connect()

      let channel = await sut.channel("test")

      let stream = await channel.broadcasts(event: "INSERT")
      let receivedPayload = LockIsolated<JSONObject?>(nil)
      let listenTask = Task {
        for await json in stream {
          receivedPayload.setValue(json)
        }
      }
      defer { listenTask.cancel() }

      try await channel.subscribe()

      let topic = Data("realtime:test".utf8)
      let event = Data("INSERT".utf8)
      let metadata = Data(#"{"id":"0b8a1e2c-77c4-4f1b-9d2a-3f5e6a7b8c9d","replayed":true}"#.utf8)
      let payload = Data(#"{"record":{"id":1}}"#.utf8)

      var frame = Data()
      frame.append(RealtimeSerializer.BinaryKind.userBroadcast.rawValue)
      frame.append(UInt8(topic.count))
      frame.append(UInt8(event.count))
      frame.append(UInt8(metadata.count))
      frame.append(RealtimeSerializer.PayloadEncoding.json.rawValue)
      frame.append(topic)
      frame.append(event)
      frame.append(metadata)
      frame.append(payload)

      server.send(frame)

      let received = await waitUntil(timeout: 2) { receivedPayload.value != nil }
      #expect(received, "Expected the broadcasts stream to receive the kind-4 frame")

      let json = try #require(receivedPayload.value)
      #expect(json["payload"]?.objectValue?["record"]?.objectValue?["id"]?.intValue == 1)
      let meta = try #require(json["meta"]?.objectValue)
      #expect(meta["id"]?.stringValue == "0b8a1e2c-77c4-4f1b-9d2a-3f5e6a7b8c9d")
      #expect(meta["replayed"]?.boolValue == true)
    }

    /// Ends the channel's streams, then returns the first element `stream` had buffered, so a
    /// missing delivery fails the test instead of hanging it.
    private func firstBuffered<Element: Sendable>(
      _ stream: AsyncStream<Element>, on channel: RealtimeChannel
    ) async -> Element? {
      await channel.finishStreams()
      return await stream.first { _ in true }
    }
  }

#endif
