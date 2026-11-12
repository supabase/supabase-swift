//
//  RealtimeWebSocketTransportV3APITests.swift
//  Supabase
//
//  Tests for the v3 WebSocket transport API that ships on the v2 line. They use the public API
//  only.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import Realtime
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A connection that records what the client sends and answers joins and heartbeats.
private final class StubConnection: WebSocketConnection {
  struct Close: Equatable {
    var code: WebSocketCloseCode
    var reason: String?
  }

  let events: AsyncStream<WebSocketEvent>
  private let continuation: AsyncStream<WebSocketEvent>.Continuation
  let sent = LockIsolated<[WebSocketFrame]>([])
  let closes = LockIsolated<[Close]>([])

  init() {
    (events, continuation) = AsyncStream.makeStream()
  }

  func send(_ frame: WebSocketFrame) async throws {
    sent.withValue { $0.append(frame) }
    guard case .text(let text) = frame,
      let message = try? JSONDecoder().decode(RealtimeMessageV2.self, from: Data(text.utf8)),
      message.event == "phx_join" || message.event == "heartbeat"
    else { return }
    let reply = RealtimeMessageV2(
      joinRef: message.joinRef, ref: message.ref, topic: message.topic, event: "phx_reply",
      payload: ["status": "ok", "response": ["postgres_changes": .array([])]])
    receive(.frame(.text(String(decoding: try JSONEncoder().encode(reply), as: UTF8.self))))
  }

  func close(code: WebSocketCloseCode, reason: String?) {
    closes.withValue { $0.append(Close(code: code, reason: reason)) }
    receive(.closed(code: code, reason: reason))
    continuation.finish()
  }

  func receive(_ event: WebSocketEvent) {
    continuation.yield(event)
  }
}

private struct StubTransport: WebSocketTransport {
  struct Request {
    var url: URL
    var headerFields: HTTPFields
  }

  let connection = StubConnection()
  let requests = LockIsolated<[Request]>([])

  func connect(to url: URL, headerFields: HTTPFields) async throws -> any WebSocketConnection {
    requests.withValue { $0.append(Request(url: url, headerFields: headerFields)) }
    return connection
  }
}

@Suite
struct RealtimeWebSocketTransportV3APITests {
  private let transport = StubTransport()

  private func makeClient() -> RealtimeClientV2 {
    var options = RealtimeClientOptions(
      headers: ["apikey": "publishable.api.key"], vsn: .v1, accessToken: { "token" })
    options.webSocketTransport = transport
    return RealtimeClientV2(
      url: URL(string: "http://localhost:54321/realtime/v1")!, options: options)
  }

  @Test
  func theOptionIsNilByDefault() {
    let options = RealtimeClientOptions(headers: ["apikey": "publishable.api.key"])

    #expect(options.webSocketTransport == nil)
  }

  @Test
  func aCustomTransportIsUsedToConnect() async throws {
    let client = makeClient()

    await client.connect()

    let request = try #require(transport.requests.value.first)
    #expect(transport.requests.value.count == 1)
    #expect(request.url.scheme == "ws")
    #expect(request.url.path == "/realtime/v1/websocket")
    #expect(request.headerFields[HTTPField.Name("apikey")!] == "publishable.api.key")
    #expect(client.status == .connected)
    client.disconnect()
  }

  @Test
  func framesFlowBothWays() async throws {
    let client = makeClient()
    await client.connect()
    let channel = client.channel("room")

    try await channel.subscribeWithError()

    let texts = transport.connection.sent.value.compactMap { frame -> String? in
      if case .text(let text) = frame { text } else { nil }
    }
    #expect(texts.contains { $0.contains("phx_join") && $0.contains("realtime:room") })
    #expect(channel.status == .subscribed)
    client.disconnect()
  }

  @Test
  func disconnectClosesTheConnectionWithNormalClosureAndTheReason() async throws {
    let client = makeClient()
    await client.connect()

    // The v2 client does not send the code of `disconnect(code:)` to its socket.
    client.disconnect(code: 4001, reason: "bye")

    // The client closes the socket from a task of its own.
    for _ in 0..<200 where transport.connection.closes.value.isEmpty {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(
      transport.connection.closes.value
        == [StubConnection.Close(code: .normalClosure, reason: "bye")])
  }

  @Test
  func aCloseFromThePeerIsReported() async throws {
    let client = makeClient()
    await client.connect()
    let statuses = await client.statusChanges()

    transport.connection.receive(.closed(code: 4002, reason: "gone"))

    for await status in statuses where status != .connected {
      break
    }
    #expect(client.status != .connected)
    client.disconnect()
  }

  @Test
  func closeCodesAndFramesAreValues() {
    #expect(WebSocketCloseCode.normalClosure == 1000)
    #expect(WebSocketCloseCode.goingAway.rawValue == 1001)
    #expect(WebSocketCloseCode.protocolError == WebSocketCloseCode(rawValue: 1002))
    #expect(WebSocketCloseCode.abnormalClosure == 1006)
    #expect(WebSocketFrame.text("a") != WebSocketFrame.binary(Data("a".utf8)))
    #expect(
      Set([WebSocketEvent.frame(.text("a")), .closed(code: 1000, reason: nil)]).count == 2)
  }

  @Test
  func theURLSessionTransportRefusesAURLThatIsNotAWebSocketURL() async throws {
    let transport = URLSessionWebSocketTransport(configuration: .ephemeral, delegate: nil)

    do {
      _ = try await transport.connect(
        to: URL(string: "http://localhost:54321")!, headerFields: HTTPFields())
      Issue.record("connect did not throw")
    } catch let error as RealtimeError {
      #expect(error.kind == .invalidRequest)
    }
  }
}
