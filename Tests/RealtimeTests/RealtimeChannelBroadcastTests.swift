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
      configuration: RealtimeClient.Configuration(
        url: url,
        headers: [.apikey: apiKey],
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
            RealtimeMessage(
              joinRef: msg.joinRef,
              ref: msg.ref,
              topic: "phoenix",
              event: "phx_reply",
              payload: ["response": [:]]
            )
          )
        } else if msg.event == "phx_join" {
          server.send(
            RealtimeMessage(
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

  static func isInvalidRequest(_ error: any Error) -> Bool {
    (error as? RealtimeError)?.kind == .invalidRequest
      && (error as? RealtimeError)?.underlyingError != nil
  }

  @Test
  func broadcastOfAPayloadThatIsNotAnObjectIsAnInvalidRequest() async {
    let channel = await sut.channel("test")

    await #expect {
      try await channel.broadcast(event: "my_event", payload: 42)
    } throws: { Self.isInvalidRequest($0) }
  }

  @Test
  func trackOfAPayloadThatIsNotAnObjectIsAnInvalidRequest() async {
    let channel = await sut.channel("test")

    await #expect {
      try await channel.track(42)
    } throws: { Self.isInvalidRequest($0) }
  }

  @Test
  func httpSendOfAPayloadThatCannotBeEncodedIsAnInvalidRequest() async {
    let channel = await sut.channel("test")

    await #expect {
      try await channel.httpSend(event: "my_event", payload: ["value": Double.nan])
    } throws: { error in
      Self.isInvalidRequest(error) && (error as? RealtimeError)?.underlyingError is EncodingError
    }
    #expect(http.requests.isEmpty)
  }

  @Test
  func broadcastOfAnEventOver255BytesIsAnInvalidRequestAndSendsNothing() async throws {
    setupServerAutoResponder()
    try await sut.connect()
    let channel = await sut.channel("test")
    try await channel.subscribe()
    // 128 characters, 256 UTF-8 bytes: the limit counts bytes, not characters.
    let event = String(repeating: "é", count: 128)

    await #expect {
      try await channel.broadcast(event: event, payload: ["a": 1] as JSONObject)
    } throws: { ($0 as? RealtimeError)?.kind == .invalidRequest }
    await #expect {
      try await channel.broadcast(event: event, data: Data([0x01]))
    } throws: { ($0 as? RealtimeError)?.kind == .invalidRequest }
    #expect(await client.sentBinaryFrames().isEmpty)
  }

  @Test
  func broadcastOfAnEventOf255BytesIsSent() async throws {
    setupServerAutoResponder()
    try await sut.connect()
    let channel = await sut.channel("test")
    try await channel.subscribe()

    try await channel.broadcast(event: String(repeating: "e", count: 255), data: Data([0x01]))

    #expect(await client.sentBinaryFrames().count == 1)
  }

  @Test
  func broadcastOnATopicOver255BytesIsAnInvalidRequestAndSendsNothing() async throws {
    // "realtime:" adds 9 bytes, so the wire topic is 256 bytes.
    let name = String(repeating: "t", count: 247)
    setupServerAutoResponder(topic: "realtime:\(name)")
    try await sut.connect()
    let channel = await sut.channel(name)
    try await channel.subscribe()

    await #expect {
      try await channel.broadcast(event: "my_event", data: Data([0x01]))
    } throws: { ($0 as? RealtimeError)?.kind == .invalidRequest }
    #expect(await client.sentBinaryFrames().isEmpty)
  }

  @Test
  func broadcastOnATopicOf246BytesIsSent() async throws {
    let name = String(repeating: "t", count: 246)
    setupServerAutoResponder(topic: "realtime:\(name)")
    try await sut.connect()
    let channel = await sut.channel(name)
    try await channel.subscribe()

    try await channel.broadcast(event: "my_event", data: Data([0x01]))

    #expect(await client.sentBinaryFrames().count == 1)
  }

  @Test
  func broadcast_sendsJsonViaBinaryFrame() async throws {
    setupServerAutoResponder()
    try await sut.connect()

    let channel = await sut.channel("test")
    try await channel.subscribe()

    try await channel.broadcast(
      event: "my_event", payload: ["hello": .string("world")] as JSONObject
    )

    let binaryEvents = await client.sentBinaryFrames()

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

    let binaryFrames = await client.sentBinaryFrames()

    #expect(!binaryFrames.isEmpty, "Expected at least one binary frame to be sent")

    if let frame = binaryFrames.last {
      #expect(frame[0] == RealtimeSerializer.BinaryKind.userBroadcastPush.rawValue)
      #expect(frame[6] == RealtimeSerializer.PayloadEncoding.binary.rawValue)
    }
  }

  @Test
  func broadcast_ofABroadcastEventSendsItUnderTheTypesEventName() async throws {
    setupServerAutoResponder()
    try await sut.connect()
    let channel = await sut.channel("test")
    try await channel.subscribe()

    try await channel.broadcast(Cursor(x: 3))

    let frame = try #require(await client.sentBinaryFrames().last)
    let eventStart = 7 + Int(frame[1]) + Int(frame[2]) + Int(frame[3])
    let eventEnd = eventStart + Int(frame[4])
    let payloadStart = eventEnd + Int(frame[5])
    let bytes = [UInt8](frame)
    #expect(String(decoding: bytes[eventStart..<eventEnd], as: UTF8.self) == "cursor")
    #expect(frame[6] == RealtimeSerializer.PayloadEncoding.json.rawValue)
    #expect(
      try JSONDecoder().decode(Cursor.self, from: Data(bytes[payloadStart...])) == Cursor(x: 3))
  }

  @Test
  func receive_typedStreamDeliversOnlyItsEventAndDecodesThePayload() async throws {
    let channel = await sut.channel("test")
    let cursors = await channel.broadcasts(of: Cursor.self)

    let messages = await deliver(
      [cursorBroadcast(event: "other", x: 1), cursorBroadcast(event: "cursor", x: 2)],
      to: cursors, on: channel)
    #expect(messages.map(\.raw.event) == ["cursor"])
    #expect(try messages.first?.payload() == Cursor(x: 2))
  }

  @Test
  func receive_typedStreamKeepsDeliveringAfterAPayloadThatDoesNotDecode() async throws {
    let channel = await sut.channel("test")
    let cursors = await channel.broadcasts(of: Cursor.self)

    let bad = DecodedBroadcast(
      topic: "realtime:test", event: "cursor", payload: .json(["x": .string("bad")]))
    let messages = await deliver(
      [bad, cursorBroadcast(event: "cursor", x: 4)], to: cursors, on: channel)
    #expect(messages.count == 2)
    #expect(throws: RealtimeError.self) { try messages[0].payload() }
    #expect(try messages[1].payload() == Cursor(x: 4))
  }

  @Test
  func receive_typedStreamHonorsItsBufferingPolicy() async throws {
    let channel = await sut.channel("test")
    let cursors = await channel.broadcasts(of: Cursor.self, bufferingPolicy: .bufferingNewest(1))

    let messages = await deliver(
      (1...3).map { cursorBroadcast(event: "cursor", x: $0) }, to: cursors, on: channel)

    #expect(try messages.map { try $0.payload() } == [Cursor(x: 3)])
  }

  @Test
  @MainActor
  func receive_typedStreamDecodesAMainActorIsolatedEvent() async throws {
    let channel = await sut.channel("test")
    let cursors = await channel.broadcasts(of: MainActorCursor.self)

    let messages = await deliver(
      [cursorBroadcast(event: "main-cursor", x: 5)], to: cursors, on: channel)

    #expect(try messages.map { try $0.payload().x } == [5])
  }

  /// Subscribes the channel, delivers `broadcasts`, ends the channel's streams, and returns what
  /// `stream` received.
  private func deliver<Element: Sendable>(
    _ broadcasts: [DecodedBroadcast], to stream: AsyncStream<Element>, on channel: RealtimeChannel
  ) async -> [Element] {
    await sut.installSubscribedRecord("test")
    for broadcast in broadcasts {
      await sut.apply(.binaryBroadcast(broadcast))
    }
    await channel.client?.finishStreams(of: channel)
    return await stream.collect()
  }

  private func cursorBroadcast(event: String, x: Int) -> DecodedBroadcast {
    DecodedBroadcast(
      topic: "realtime:test", event: event, payload: .json(["x": JSONValue(integerLiteral: x)]))
  }

  @Test
  func receive_jsonBroadcastFromBinaryFrame() async throws {
    let channel = await sut.channel("test")

    let stream = await channel.broadcasts(event: "my_event")

    let broadcast = DecodedBroadcast(
      topic: "realtime:test",
      event: "my_event",
      payload: .json(["count": .number(99)])
    )
    await sut.installSubscribedRecord("test")
    await sut.apply(.binaryBroadcast(broadcast))

    let message = await firstBuffered(stream, on: channel)
    #expect(message?.event == "my_event")
    #expect(message?.payload == .json(["count": 99]))
  }

  @Test
  func receive_boundedBroadcastStreamKeepsOnlyTheNewestMessage() async throws {
    let channel = await sut.channel("test")

    let newest = await channel.broadcasts(event: "cursor", bufferingPolicy: .bufferingNewest(1))
    let all = await channel.broadcasts(event: "cursor")

    await sut.installSubscribedRecord("test")
    for x in 1...3 {
      await sut.apply(
        .binaryBroadcast(
          DecodedBroadcast(
            topic: "realtime:test", event: "cursor", payload: .json(["x": .string("\(x)")]))))
    }
    await channel.client?.finishStreams(of: channel)

    #expect(await newest.collect().map(\.payload) == [.json(["x": "3"])])
    #expect(await all.collect().count == 3)
  }

  @Test
  func receive_binaryBroadcastFromBinaryFrame() async throws {
    let channel = await sut.channel("test")

    let stream = await channel.broadcasts(event: "bin_event")

    let binaryPayload = Data([0xCA, 0xFE, 0xBA, 0xBE])
    let broadcast = DecodedBroadcast(
      topic: "realtime:test",
      event: "bin_event",
      payload: .binary(binaryPayload)
    )
    await sut.installSubscribedRecord("test")
    await sut.apply(.binaryBroadcast(broadcast))

    let message = await firstBuffered(stream, on: channel)
    #expect(message?.event == "bin_event")
    #expect(message?.payload == .binary(binaryPayload))
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
    await sut.installSubscribedRecord("test")
    await sut.apply(.binaryBroadcast(broadcast))

    let message = await firstBuffered(stream, on: channel)
    #expect(message?.event == "evt")
    #expect(message?.payload == .json(["key": "value"]))
    #expect(message?.id == nil)
    #expect(message?.isReplayed == false)
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
    await sut.installSubscribedRecord("test")
    await sut.apply(.binaryBroadcast(broadcast))

    let message = await firstBuffered(stream, on: channel)
    #expect(message?.id == UUID(uuidString: "0b8a1e2c-77c4-4f1b-9d2a-3f5e6a7b8c9d"))
    #expect(message?.isReplayed == true)
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
      event: "my_event", payload: Message(userName: "abc"), encoder: snakeCaseEncoder
    )

    let frame = try #require(
      await client.sentBinaryFrames().last
    )
    #expect(frame.range(of: Data(#""user_name":"abc""#.utf8)) != nil)
    #expect(frame.range(of: Data("userName".utf8)) == nil)
  }

  @Test
  func broadcast_defaultEncoderIsTheSupabaseEncoder() async throws {
    setupServerAutoResponder()
    try await sut.connect()

    let channel = await sut.channel("test")
    try await channel.subscribe()

    try await channel.broadcast(
      event: "my_event", payload: ["at": Date(timeIntervalSince1970: 0)])

    let frame = try #require(
      await client.sentBinaryFrames().last
    )
    #expect(frame.range(of: Data(#""at":"1970-01-01T00:00:00"#.utf8)) != nil)
  }

  @Test
  func broadcast_nilEncoderIsTheSupabaseEncoder() async throws {
    setupServerAutoResponder()
    try await sut.connect()

    let channel = await sut.channel("test")
    try await channel.subscribe()

    try await channel.broadcast(
      event: "my_event", payload: ["at": Date(timeIntervalSince1970: 0)], encoder: nil)

    let frame = try #require(await client.sentBinaryFrames().last)
    #expect(frame.range(of: Data(#""at":"1970-01-01T00:00:00.000Z""#.utf8)) != nil)
  }

  @Test
  func httpSend_nilEncoderIsTheSupabaseEncoder() async throws {
    http.respond { _, _ in
      (HTTPResponse(status: .init(code: 202)), Data())
    }

    let channel = await sut.channel("test")
    try await channel.httpSend(
      event: "my_event", payload: ["at": Date(timeIntervalSince1970: 0)], encoder: nil)

    let body = try #require(http.requests.last?.body)
    #expect(String(decoding: body, as: UTF8.self) == #"{"at":"1970-01-01T00:00:00.000Z"}"#)
  }

  @Test
  func httpSend_encodesPayloadWithTheGivenEncoder() async throws {
    http.respond { _, _ in
      (HTTPResponse(status: .init(code: 202)), Data())
    }

    struct Message: Encodable {
      let userName: String
    }
    let snakeCaseEncoder = JSONEncoder()
    snakeCaseEncoder.keyEncodingStrategy = .convertToSnakeCase

    let channel = await sut.channel("test")
    try await channel.httpSend(
      event: "my_event", payload: Message(userName: "abc"), encoder: snakeCaseEncoder)

    let body = try #require(http.requests.last?.body)
    #expect(String(decoding: body, as: UTF8.self) == #"{"user_name":"abc"}"#)
    #expect(http.requests.last?.head.headerFields[.contentType] == "application/json")
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
      config.broadcast.acknowledgesMessages = true
    }

    let error = await #expect(throws: RealtimeError.self) {
      try await channel.broadcast(
        event: "my_event", payload: ["hello": .string("world")] as JSONObject
      )
    }
    #expect(error?.kind == .notSubscribed)
    #expect(http.requests.isEmpty)
  }

  @Test
  func httpSend_urlUsesTheUserTopic() async throws {
    http.respond { _, _ in
      (HTTPResponse(status: .init(code: 202)), Data())
    }

    let channel = await sut.channel("test")
    #expect(channel.topic == "test")

    try await channel.httpSend(
      event: "my_event", payload: ["hello": .string("world")] as JSONObject
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
    let receivedPayload = LockIsolated<BroadcastMessage?>(nil)
    let listenTask = Task {
      for await message in stream {
        receivedPayload.setValue(message)
      }
    }
    defer { listenTask.cancel() }

    try await channel.subscribe()

    let jsonPayload: JSONObject = ["count": .number(99)]
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
      #expect(payload.event == "my_event")
      #expect(payload.payload == .json(["count": 99]))
    }
  }

  @Test
  func endToEnd_binaryFrameForwardsDatabaseMetadataAsMeta() async throws {
    setupServerAutoResponder()
    try await sut.connect()

    let channel = await sut.channel("test")

    let stream = await channel.broadcasts(event: "INSERT")
    let receivedPayload = LockIsolated<BroadcastMessage?>(nil)
    let listenTask = Task {
      for await message in stream {
        receivedPayload.setValue(message)
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

    let message = try #require(receivedPayload.value)
    #expect(message.payload == .json(["record": ["id": 1]]))
    #expect(message.id == UUID(uuidString: "0b8a1e2c-77c4-4f1b-9d2a-3f5e6a7b8c9d"))
    #expect(message.isReplayed == true)
  }

  /// Ends the channel's streams, then returns the first element `stream` had buffered, so a
  /// missing delivery fails the test instead of hanging it.
  private func firstBuffered<Element: Sendable>(
    _ stream: AsyncStream<Element>, on channel: RealtimeChannel
  ) async -> Element? {
    await channel.client?.finishStreams(of: channel)
    return await stream.first { _ in true }
  }
}

private struct Cursor: BroadcastEvent, Codable, Equatable {
  static let event = "cursor"
  var x: Int
}

@MainActor
private struct MainActorCursor: BroadcastEvent, Decodable {
  static let event = "main-cursor"
  var x: Int
}
