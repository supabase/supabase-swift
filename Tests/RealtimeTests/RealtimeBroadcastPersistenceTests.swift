//
//  RealtimeBroadcastPersistenceTests.swift
//  RealtimeTests
//

import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@testable import Realtime

/// `persist` on ``RealtimeChannel/broadcast(event:payload:persist:encoder:)`` and
/// ``RealtimeChannel/httpSend(event:payload:persist:timeout:encoder:)``.
@Suite
struct RealtimeBroadcastPersistenceTests {
  // MARK: WebSocket

  @Test
  func broadcastWithoutPersistSendsNoMetadata() async throws {
    let host = await RealtimeTestHost()
    let channel = try await subscribedChannel(on: host, isPrivate: true)

    try await channel.broadcast(event: "message", payload: ["text": "hi"] as JSONObject)

    let frame = try await lastBroadcastFrame(on: host)
    #expect(frame.metadata.isEmpty)
  }

  @Test
  func broadcastWithPersistSendsItInTheFrameMetadata() async throws {
    let host = await RealtimeTestHost()
    let channel = try await subscribedChannel(on: host, isPrivate: true)

    try await channel.broadcast(
      event: "message", payload: ["text": "hi"] as JSONObject, persist: BroadcastPersistence())

    let frame = try await lastBroadcastFrame(on: host)
    #expect(try JSONDecoder().decode(JSONValue.self, from: frame.metadata) == ["persist": true])
    #expect(try JSONDecoder().decode(JSONValue.self, from: frame.payload) == ["text": "hi"])
  }

  @Test
  func broadcastWithTTLSendsItsWholeSecondsInTheFrameMetadata() async throws {
    let host = await RealtimeTestHost()
    let channel = try await subscribedChannel(on: host, isPrivate: true)

    try await channel.broadcast(
      event: "cursor", data: Data([0x01]),
      persist: BroadcastPersistence(ttl: .milliseconds(3_600_500)))

    let frame = try await lastBroadcastFrame(on: host)
    #expect(
      try JSONDecoder().decode(JSONValue.self, from: frame.metadata)
        == ["persist": ["ttl": 3600]])
    #expect(frame.payload == Data([0x01]))
  }

  @Test
  func broadcastSendsAnOutOfRangeTtlAsGiven() async throws {
    let host = await RealtimeTestHost()
    let channel = try await subscribedChannel(on: host, isPrivate: true)

    try await channel.broadcast(
      Cursor(x: 1), persist: BroadcastPersistence(ttl: .seconds(-5)))

    let frame = try await lastBroadcastFrame(on: host)
    #expect(
      try JSONDecoder().decode(JSONValue.self, from: frame.metadata)
        == ["persist": ["ttl": -5]])
  }

  @Test
  func broadcastWithPersistOnAPublicChannelIsAnInvalidRequestAndSendsNothing() async throws {
    let host = await RealtimeTestHost()
    let channel = try await subscribedChannel(on: host, isPrivate: false)
    let persist = BroadcastPersistence()

    await expectNotPrivate {
      try await channel.broadcast(event: "e", payload: ["a": 1] as JSONObject, persist: persist)
    }
    await expectNotPrivate {
      try await channel.broadcast(event: "e", data: Data(), persist: persist)
    }
    await expectNotPrivate { try await channel.broadcast(Cursor(x: 1), persist: persist) }

    let socket = try #require(host.sockets.last)
    #expect(await socket.sentBinaryFrames(timeout: .milliseconds(200)).isEmpty)
  }

  @Test(arguments: [
    ("persistence_unauthorized", RealtimeError.Code.persistenceUnauthorized),
    ("persistence_failed", RealtimeError.Code.persistenceFailed),
    ("persistence_invalid_ttl", RealtimeError.Code.persistenceInvalidTTL),
  ])
  func acknowledgedBroadcastThatWasNotStoredThrowsTheServerCode(
    reply: String, code: RealtimeError.Code
  ) async throws {
    let host = await RealtimeTestHost()
    let channel = try await subscribedChannel(
      on: host, isPrivate: true, acknowledgesMessages: true)

    let send = Task {
      try await channel.broadcast(
        event: "message", payload: ["text": "hi"] as JSONObject, persist: BroadcastPersistence())
    }
    defer { send.cancel() }
    let frame = try await lastBroadcastFrame(on: host)
    host.server?.send(
      RealtimeMessage(
        joinRef: frame.joinRef, ref: frame.ref, topic: channel.wireTopic, event: "phx_reply",
        payload: ["status": "error", "response": ["error": .string(reply)]]))

    let error = await #expect(throws: RealtimeError.self) { try await acknowledgement(of: send) }
    #expect(error?.kind == .server)
    #expect(error?.code == code)
  }

  @Test
  func acknowledgedBroadcastThatWasStoredReturns() async throws {
    let host = await RealtimeTestHost()
    let channel = try await subscribedChannel(
      on: host, isPrivate: true, acknowledgesMessages: true)

    let send = Task {
      try await channel.broadcast(
        event: "message", payload: ["text": "hi"] as JSONObject, persist: BroadcastPersistence())
    }
    defer { send.cancel() }
    let frame = try await lastBroadcastFrame(on: host)
    host.server?.send(
      RealtimeMessage(
        joinRef: frame.joinRef, ref: frame.ref, topic: channel.wireTopic, event: "phx_reply",
        payload: ["status": "ok", "response": [:]]))

    try await acknowledgement(of: send)
  }

  // MARK: REST

  @Test
  func httpSendWithoutPersistSendsNoPersistQuery() async throws {
    let http = Self.acceptingTransport()
    let host = await RealtimeTestHost(http: HTTPClient(transport: http))
    let channel = await host.client.channel("room") { $0.isPrivate = true }

    try await channel.httpSend(event: "message", payload: ["text": "hi"] as JSONObject)

    #expect(try Self.queryItems(of: http) == [URLQueryItem(name: "private", value: "true")])
  }

  @Test
  func httpSendWithPersistSendsItInTheQueryString() async throws {
    let http = Self.acceptingTransport()
    let host = await RealtimeTestHost(http: HTTPClient(transport: http))
    let channel = await host.client.channel("room") { $0.isPrivate = true }

    try await channel.httpSend(
      event: "message", payload: ["text": "hi"] as JSONObject, persist: BroadcastPersistence())

    #expect(
      try Self.queryItems(of: http) == [
        URLQueryItem(name: "private", value: "true"),
        URLQueryItem(name: "persist", value: "true"),
      ])
    let body = try #require(http.requests.last?.body)
    #expect(try JSONDecoder().decode(JSONValue.self, from: body) == ["text": "hi"])
  }

  @Test
  func httpSendWithTTLSendsItsWholeSecondsInTheQueryString() async throws {
    let http = Self.acceptingTransport()
    let host = await RealtimeTestHost(http: HTTPClient(transport: http))
    let channel = await host.client.channel("room") { $0.isPrivate = true }

    try await channel.httpSend(
      event: "message", data: Data([0x01]), persist: BroadcastPersistence(ttl: .seconds(3600)))

    #expect(
      try Self.queryItems(of: http) == [
        URLQueryItem(name: "private", value: "true"),
        URLQueryItem(name: "persist[ttl]", value: "3600"),
      ])
    #expect(http.requests.last?.body == Data([0x01]))
  }

  @Test
  func httpSendWithPersistOnAPublicChannelIsAnInvalidRequestAndSendsNothing() async throws {
    let http = Self.acceptingTransport()
    let host = await RealtimeTestHost(http: HTTPClient(transport: http))
    let channel = await host.client.channel("room")
    let persist = BroadcastPersistence()

    await expectNotPrivate {
      try await channel.httpSend(event: "e", payload: ["a": 1] as JSONObject, persist: persist)
    }
    await expectNotPrivate {
      try await channel.httpSend(event: "e", data: Data(), persist: persist)
    }

    #expect(http.requests.isEmpty)
  }

  @Test
  func httpSendThrowsTheServerMessageWhenTheServerRefusesTheTTL() async throws {
    let message = "persist ttl must be a positive integer of seconds from 1 to 259200"
    let http = RecordingTransport()
    http.respond { _, _ in
      (HTTPResponse(status: .init(code: 422)), Data(#"{"message":"\#(message)"}"#.utf8))
    }
    let host = await RealtimeTestHost(http: HTTPClient(transport: http))
    let channel = await host.client.channel("room") { $0.isPrivate = true }

    let error = await #expect(throws: RealtimeError.self) {
      try await channel.httpSend(
        event: "e", payload: ["a": 1] as JSONObject,
        persist: BroadcastPersistence(ttl: .seconds(0)))
    }
    #expect(error?.kind == .server)
    #expect(error?.message == message)
    #expect(error?.response?.status.code == 422)
  }

  // MARK: Helpers

  private struct Cursor: BroadcastEvent, Codable {
    static let event = "cursor"
    var x: Int
  }

  /// A user broadcast push frame the client sent, split into its fields.
  private struct BroadcastFrame {
    var joinRef: String
    var ref: String
    var metadata: Data
    var payload: Data

    init(_ frame: Data) {
      let bytes = [UInt8](frame)
      var offset = 7
      func field(_ length: UInt8) -> ArraySlice<UInt8> {
        defer { offset += Int(length) }
        return bytes[offset..<offset + Int(length)]
      }
      joinRef = String(decoding: field(bytes[1]), as: UTF8.self)
      ref = String(decoding: field(bytes[2]), as: UTF8.self)
      _ = field(bytes[3])
      _ = field(bytes[4])
      metadata = Data(field(bytes[5]))
      payload = Data(bytes[offset...])
    }
  }

  private func subscribedChannel(
    on host: RealtimeTestHost, isPrivate: Bool, acknowledgesMessages: Bool = false
  ) async throws -> RealtimeChannel {
    let channel = await host.client.channel("room") {
      $0.isPrivate = isPrivate
      $0.broadcast.acknowledgesMessages = acknowledgesMessages
    }
    try await host.subscribe(channel)
    return channel
  }

  private func lastBroadcastFrame(on host: RealtimeTestHost) async throws -> BroadcastFrame {
    let socket = try #require(host.sockets.last)
    return BroadcastFrame(try #require(await socket.sentBinaryFrames().last))
  }

  /// Waits for `send` to finish, bounded on the wall clock: the push deadline runs on the host's
  /// test clock, which these tests do not advance, so a reply that never arrives fails the test
  /// instead of hanging it. Cancels `send` when the bound expires.
  private func acknowledgement(of send: Task<Void, any Error>) async throws {
    try await withTimeout(.seconds(5)) {
      try await withTaskCancellationHandler {
        try await send.value
      } onCancel: {
        send.cancel()
      }
    }
  }

  private func expectNotPrivate(
    _ send: () async throws -> Void, sourceLocation: SourceLocation = #_sourceLocation
  ) async {
    let error = await #expect(throws: RealtimeError.self, sourceLocation: sourceLocation) {
      try await send()
    }
    #expect(error?.kind == .invalidRequest, sourceLocation: sourceLocation)
  }

  private static func acceptingTransport() -> RecordingTransport {
    let http = RecordingTransport()
    http.respond { _, _ in (HTTPResponse(status: .init(code: 202)), Data()) }
    return http
  }

  private static func queryItems(of http: RecordingTransport) throws -> [URLQueryItem] {
    let url = try #require(http.requests.last?.head.url)
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
  }
}
