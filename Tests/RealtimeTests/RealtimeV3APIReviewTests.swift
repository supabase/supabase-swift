//
//  RealtimeV3APIReviewTests.swift
//  Supabase
//
//  Tests for the v3 API on the v2 line that need the test doubles of this target.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Realtime
@testable import RealtimeV2

#if !os(Linux)
  /// An error type an app owns. It has the same conformances as `RealtimeError.Code`.
  private struct AppError: Error, Equatable, ExpressibleByStringLiteral {
    var name: String

    init(stringLiteral value: String) {
      name = value
    }
  }

  @Suite
  struct RealtimeV3APIReviewTests {
    let fixture = RealtimeV3Fixture()

    private func diffMessage(_ ref: Int) -> RealtimeMessageV2 {
      RealtimeMessageV2(
        joinRef: nil, ref: nil, topic: "realtime:test", event: "presence_diff",
        payload: [
          "joins": ["user": ["metas": [["phx_ref": .string("r\(ref)")]]]],
          "leaves": [:],
        ])
    }

    @Test
    func aChannelWithNoPresenceObserverKeepsNoDiff() async throws {
      let channel = try await fixture.subscribedChannel()

      for ref in 0..<200 {
        await channel.onMessage(diffMessage(ref))
      }

      #expect(channel.presenceTracker.value.pendingDiffCount == 0)
      #expect(await channel.presenceState == PresenceState())
    }

    @Test
    func aPresenceStreamStillQueuesDiffsUntilTheState() async throws {
      let channel = fixture.sut.channel("test")
      let states = await channel.presenceStates()

      await channel.onMessage(diffMessage(1))
      #expect(channel.presenceTracker.value.pendingDiffCount == 1)
      await channel.onMessage(
        RealtimeMessageV2(
          joinRef: nil, ref: nil, topic: "realtime:test", event: "presence_state", payload: [:]))

      #expect(channel.presenceTracker.value.pendingDiffCount == 0)
      #expect(await channel.presenceState.entries["user"]?.map(\.ref) == ["r1"])
      _ = states
    }

    @Test
    func isEnabledTurnsPresenceOnForTheJoinWithNoStream() async throws {
      let joins = LockIsolated<[RealtimeMessageV2]>([])
      let task = Task { @Sendable [server = fixture.server] in
        for await event in server.events {
          guard let message = event.realtimeMessage, message.event == "phx_join" else { continue }
          joins.withValue { $0.append(message) }
          server.send(
            RealtimeMessageV2(
              joinRef: message.joinRef, ref: message.ref, topic: "realtime:test",
              event: "phx_reply",
              payload: ["response": ["postgres_changes": .array([])], "status": "ok"]))
        }
      }
      defer { task.cancel() }
      await fixture.sut.connect()
      let channel = fixture.sut.channel("test") { $0.presence.isEnabled = true }

      try await channel.subscribeWithError()

      let presence = joins.value.first?.payload["config"]?.objectValue?["presence"]?.objectValue
      #expect(presence == ["key": "", "enabled": true])
      #expect(RealtimeChannelConfiguration().presence.isEnabled == false)
    }

    @Test
    func anUnappliedHTTPSendReferenceKeepsTheTimeIntervalOverload() async throws {
      await fixture.acceptBroadcastsOverREST()
      let channel = fixture.sut.channel("room")

      let send = channel.httpSend(event:data:timeout:)
      try await send("cursor", Data([1]), 5.0)

      #expect(await fixture.http.receivedRequests.count == 1)
    }

    @Test
    func theURLSessionConnectionMapsTheEventsOfItsSocket() async throws {
      let (socket, peer) = FakeWebSocket.fakes()
      let connection = URLSessionWebSocketConnection(socket)
      var events = connection.events.makeAsyncIterator()

      peer.send("hello")
      peer.send(Data([1, 2]))
      peer.close(code: 4001, reason: "gone")

      #expect(await events.next() == .frame(.text("hello")))
      #expect(await events.next() == .frame(.binary(Data([1, 2]))))
      #expect(await events.next() == .closed(code: 4001, reason: "gone"))
      #expect(await events.next() == nil)
    }

    @Test
    func theURLSessionConnectionSendsFrames() async throws {
      let (socket, _) = FakeWebSocket.fakes()
      let connection = URLSessionWebSocketConnection(socket)

      try await connection.send(.text("hello"))
      try await connection.send(.binary(Data([1])))

      #expect(socket.sentEvents == [.text("hello"), .binary(Data([1]))])
    }

    @Test(arguments: [
      (WebSocketCloseCode.normalClosure, 1000 as Int?),
      (WebSocketCloseCode(rawValue: 4001), 4001),
      (WebSocketCloseCode.goingAway, nil),
      (WebSocketCloseCode.protocolError, nil),
      (WebSocketCloseCode.abnormalClosure, nil),
      (WebSocketCloseCode(rawValue: 99), nil),
    ])
    func theURLSessionConnectionSendsOnlyTheCloseCodesItsSocketAccepts(
      code: WebSocketCloseCode, sent: Int?
    ) {
      let (socket, _) = FakeWebSocket.fakes()
      let connection = URLSessionWebSocketConnection(socket)

      connection.close(code: code, reason: "bye")

      #expect(socket.sentEvents == [.close(code: sent, reason: "bye")])
    }

    @Test
    func theURLSessionConnectionCutsAReasonThatIsTooLong() {
      let (socket, _) = FakeWebSocket.fakes()
      let connection = URLSessionWebSocketConnection(socket)

      connection.close(code: .normalClosure, reason: String(repeating: "é", count: 100))

      #expect(socket.closeReason == String(repeating: "é", count: 61))
    }

    @Test
    func aStringLiteralPatternOfAnAppErrorTypeStillCompiles() {
      func name(of error: AppError) -> String {
        switch error {
        case "offline": "offline"
        default: "other"
        }
      }

      #expect(name(of: "offline") == "offline")
      #expect(name(of: "busy") == "other")
    }

    @Test
    func aCatchClauseStillMatchesAKindAndACode() {
      func kind(_ error: any Error) -> String {
        do { throw error } catch RealtimeError.Kind.timeout { return "timeout" } catch RealtimeError
          .Code.privateOnly
        { return "privateOnly" } catch { return "other" }
      }

      #expect(kind(RealtimeError(kind: .timeout, message: "")) == "timeout")
      #expect(kind(RealtimeError(kind: .server, message: "", code: .privateOnly)) == "privateOnly")
      #expect(kind(CancellationError()) == "other")
    }

    @Test
    func upgradeFailedPicksTheKindFromTheStatus() {
      #expect(RealtimeError.upgradeFailed(status: 401).kind == .unauthorized)
      #expect(RealtimeError.upgradeFailed(status: 403).kind == .unauthorized)
      #expect(RealtimeError.upgradeFailed(status: 429).kind == .rateLimited)
      #expect(RealtimeError.upgradeFailed(status: 503).kind == .server)
      let error = RealtimeError.upgradeFailed(status: 404, underlyingError: CancellationError())
      #expect(error.message == "WebSocket upgrade failed with HTTP status 404.")
      #expect(error.underlyingError is CancellationError)
    }
  }
#endif
