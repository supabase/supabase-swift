//
//  RealtimeV3APIBehaviorTests.swift
//  Supabase
//
//  Behaviour tests for the v3 public API that ships on the v2 line. They drive a client through
//  the test doubles of this target, so they need `@testable` imports.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Realtime
@testable import RealtimeV2

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

#if !os(Linux)

  final class RealtimeV3Fixture: Sendable {
    let server: FakeWebSocket
    let client: FakeWebSocket
    let http = HTTPClientMock()
    let sut: RealtimeClientV2
    let serverTask = LockIsolated<Task<Void, Never>?>(nil)

    init(vsn: RealtimeProtocolVersion = .v2) {
      let (client, server) = FakeWebSocket.fakes()
      self.client = client
      self.server = server
      sut = RealtimeClientV2(
        url: URL(string: "http://localhost:54321/realtime/v1")!,
        options: RealtimeClientOptions(
          headers: ["apikey": "publishable.api.key"],
          vsn: vsn,
          accessToken: { "custom.access.token" }
        ),
        wsTransport: { _, _ in client },
        http: http,
        clock: ContinuousClock()
      )
    }

    deinit {
      serverTask.value?.cancel()
      sut.disconnect()
    }

    func acceptBroadcastsOverREST() async {
      await http.when({ _ in true }) { _ in
        HTTPResponse(
          data: Data(),
          response: HTTPURLResponse(
            url: URL(string: "http://localhost:54321/api/broadcast")!,
            statusCode: 202,
            httpVersion: nil,
            headerFields: nil
          )!
        )
      }
    }

    /// Answers heartbeats and joins, as the Realtime server does.
    func startServer(topic: String = "realtime:test") {
      let task = Task { @Sendable [server] in
        for await event in server.events {
          guard let message = event.realtimeMessage else { continue }

          if message.event == "heartbeat" {
            server.send(
              RealtimeMessageV2(
                joinRef: message.joinRef, ref: message.ref, topic: "phoenix",
                event: "phx_reply", payload: ["response": [:], "status": "ok"]))
          } else if message.event == "phx_join" {
            server.send(
              RealtimeMessageV2(
                joinRef: message.joinRef, ref: message.ref, topic: topic,
                event: "phx_reply",
                payload: ["response": ["postgres_changes": .array([])], "status": "ok"]))
          }
        }
      }
      serverTask.setValue(task)
    }

    func subscribedChannel(
      _ topic: String = "test",
      configure: (inout RealtimeChannelConfiguration) -> Void = { _ in }
    ) async throws -> RealtimeChannelV2 {
      startServer(topic: "realtime:\(topic)")
      await sut.connect()
      let channel = sut.channel(topic, configure: configure)
      try await channel.subscribeWithError()
      return channel
    }
  }

  @Suite
  struct RealtimePushV3APITests {
    struct Cursor: Encodable {
      var positionX: Int
    }

    struct Player: Codable, Equatable {
      var name: String
    }

    let fixture = RealtimeV3Fixture()

    @Test
    func httpSendWithPayloadPostsTheEncodedBody() async throws {
      await fixture.acceptBroadcastsOverREST()
      let channel = fixture.sut.channel("room")
      let encoder = JSONEncoder()
      encoder.keyEncodingStrategy = .convertToSnakeCase

      try await channel.httpSend(
        event: "cursor", payload: Cursor(positionX: 4), encoder: encoder, timeout: .seconds(3))

      let request = try #require(await fixture.http.receivedRequests.first)
      #expect(
        request.url.absoluteString
          == "http://localhost:54321/realtime/v1/api/broadcast/room/events/cursor")
      #expect(request.headers[.contentType] == "application/json")
      #expect(request.headers[.authorization] == "Bearer custom.access.token")
      let body = try JSONDecoder().decode([String: Int].self, from: request.body ?? Data())
      #expect(body == ["position_x": 4])
    }

    @Test
    func httpSendWithPayloadUsesTheDefaultEncoder() async throws {
      await fixture.acceptBroadcastsOverREST()
      let channel = fixture.sut.channel("room")

      try await channel.httpSend(event: "player", payload: Player(name: "Ana"))

      let request = try #require(await fixture.http.receivedRequests.first)
      let body = try JSONDecoder().decode(Player.self, from: request.body ?? Data())
      #expect(body == Player(name: "Ana"))
    }

    @Test
    func httpSendWithPayloadThatDoesNotEncodeSendsNothing() async throws {
      struct Failing: Encodable {
        struct Failure: Error {}
        func encode(to encoder: any Encoder) throws { throw Failure() }
      }
      await fixture.acceptBroadcastsOverREST()
      let channel = fixture.sut.channel("room")

      do {
        try await channel.httpSend(event: "cursor", payload: Failing())
        Issue.record("expected httpSend to throw")
      } catch let error as RealtimeError {
        #expect(error.kind == .invalidRequest)
        #expect(error.underlyingError is Failing.Failure)
      }
      #expect(await fixture.http.receivedRequests.isEmpty)
    }

    @Test
    func httpSendWithDataTakesADurationTimeout() async throws {
      await fixture.acceptBroadcastsOverREST()
      let channel = fixture.sut.channel("room")

      try await channel.httpSend(event: "frame", data: Data([1, 2]), timeout: .seconds(3))

      let request = try #require(await fixture.http.receivedRequests.first)
      #expect(request.headers[.contentType] == "application/octet-stream")
      #expect(request.body == Data([1, 2]))
    }

    @Test
    func v2HTTPSendCallSitesKeepTheirMeaning() async throws {
      await fixture.acceptBroadcastsOverREST()
      let channel = fixture.sut.channel("room")
      let interval: TimeInterval = 3
      let optionalInterval: TimeInterval? = nil

      try await channel.httpSend(event: "frame", data: Data([1]))
      try await channel.httpSend(event: "frame", data: Data([2]), timeout: 3)
      try await channel.httpSend(event: "frame", data: Data([3]), timeout: 3.0)
      try await channel.httpSend(event: "frame", data: Data([4]), timeout: interval)
      try await channel.httpSend(event: "frame", data: Data([5]), timeout: optionalInterval)
      try await channel.httpSend(event: "frame", data: Data([6]), timeout: nil)
      try await channel.httpSend(event: "json", message: ["a": 1])
      try await channel.httpSend(event: "json", message: ["a": 1], timeout: 3.0)
      try await channel.httpSend(event: "json", message: Player(name: "Ana"))

      let requests = await fixture.http.receivedRequests
      #expect(requests.count == 9)
      #expect(requests.prefix(6).map(\.body) == (1...6).map { Data([UInt8($0)]) })
    }

    @Test
    func broadcastWithPayloadFallsBackToRESTWhenNotSubscribed() async throws {
      await fixture.acceptBroadcastsOverREST()
      let channel = fixture.sut.channel("room") { $0.broadcast.acknowledgesMessages = true }

      try await channel.broadcast(event: "player", payload: Player(name: "Ana"))

      let request = try #require(await fixture.http.receivedRequests.first)
      #expect(
        request.url.absoluteString
          == "http://localhost:54321/realtime/v1/api/broadcast/room/events/player")
      let body = try JSONDecoder().decode(Player.self, from: request.body ?? Data())
      #expect(body == Player(name: "Ana"))
    }

    @Test
    func broadcastWithPayloadUsesTheSocketWhenSubscribed() async throws {
      let channel = try await fixture.subscribedChannel()
      let encoder = JSONEncoder()
      encoder.keyEncodingStrategy = .convertToSnakeCase

      try await channel.broadcast(event: "cursor", payload: Cursor(positionX: 4), encoder: encoder)

      let frame = try #require(
        fixture.client.sentEvents.compactMap { event -> Data? in
          if case .binary(let data) = event { return data }
          return nil
        }.last)
      #expect(frame[0] == RealtimeSerializer.BinaryKind.userBroadcastPush.rawValue)
      #expect(String(decoding: frame, as: UTF8.self).contains(#"{"position_x":4}"#))
      #expect(await fixture.http.receivedRequests.isEmpty)
    }

    @Test
    func broadcastWithPayloadThatIsNotAJSONObjectThrows() async throws {
      let channel = fixture.sut.channel("room")

      do {
        try await channel.broadcast(event: "count", payload: 5)
        Issue.record("expected broadcast to throw")
      } catch let error as RealtimeError {
        #expect(error.kind == .invalidRequest)
      }
      #expect(await fixture.http.receivedRequests.isEmpty)
    }

    @Test
    func v2BroadcastCallSitesKeepTheirMeaning() async throws {
      await fixture.acceptBroadcastsOverREST()
      let channel = fixture.sut.channel("room") { $0.broadcast.acknowledgesMessages = true }

      await channel.broadcast(event: "json", message: ["a": 1])
      try await channel.broadcast(event: "json", message: Player(name: "Ana"))

      #expect(await fixture.http.receivedRequests.count == 2)
    }

    @Test
    func trackWithEncoderSendsThePresencePayload() async throws {
      let channel = try await fixture.subscribedChannel()
      let encoder = JSONEncoder()
      encoder.keyEncodingStrategy = .convertToSnakeCase

      try await channel.track(Cursor(positionX: 4), encoder: encoder)
      try await channel.track(Cursor(positionX: 5))

      let tracked = fixture.client.sentEvents.compactMap(\.realtimeMessage)
        .filter { $0.event == "presence" && $0.payload["event"]?.stringValue == "track" }
        .map { $0.payload["payload"] }
      #expect(tracked == [["position_x": 4], ["positionX": 5]])
    }

    @Test
    func trackWithPayloadThatIsNotAJSONObjectThrows() async throws {
      let channel = try await fixture.subscribedChannel()

      do {
        try await channel.track(["a", "b"], encoder: nil)
        Issue.record("expected track to throw")
      } catch let error as RealtimeError {
        #expect(error.kind == .invalidRequest)
      }
    }

    @Test
    func v2TrackCallSitesKeepTheirMeaning() async throws {
      let channel = try await fixture.subscribedChannel()

      try await channel.track(Player(name: "Ana"))
      await channel.track(state: ["name": "Bia"])

      let tracked = fixture.client.sentEvents.compactMap(\.realtimeMessage)
        .filter { $0.event == "presence" && $0.payload["event"]?.stringValue == "track" }
        .map { $0.payload["payload"] }
      #expect(tracked == [["name": "Ana"], ["name": "Bia"]])
    }
  }

#endif
