//
//  RealtimeV3APIBehaviorTests.swift
//  Supabase
//
//  Behavior tests for the v3 public API that ships on the v2 line. They drive a client through
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

    init(vsn: RealtimeProtocolVersion = .v2, heartbeatInterval: TimeInterval = 25) {
      let (client, server) = FakeWebSocket.fakes()
      self.client = client
      self.server = server
      sut = RealtimeClientV2(
        url: URL(string: "http://localhost:54321/realtime/v1")!,
        options: RealtimeClientOptions(
          headers: ["apikey": "publishable.api.key"],
          heartbeatInterval: heartbeatInterval,
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
    func broadcastWithPayloadThatIsNotOneJSONObjectThrows() async throws {
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
    func trackWithPayloadThatIsNotOneJSONObjectThrows() async throws {
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

  @Suite
  struct RealtimeStatusStreamsV3APITests {
    let fixture = RealtimeV3Fixture()

    @Test
    func clientStatusChangesStartsWithTheCurrentStatusAndFollowsTheConnection() async {
      fixture.startServer()
      var statuses = await fixture.sut.statusChanges().makeAsyncIterator()

      #expect(await statuses.next() == .disconnected)

      await fixture.sut.connect()
      #expect(await statuses.next() == .connecting)
      #expect(await statuses.next() == .connected)

      fixture.sut.disconnect()
      #expect(await statuses.next() == .disconnected)
    }

    @Test
    func channelStatusChangesStartsWithTheCurrentStatusAndFollowsTheSubscription() async throws {
      fixture.startServer()
      await fixture.sut.connect()
      let channel = fixture.sut.channel("test")
      var statuses = await channel.statusChanges().makeAsyncIterator()

      #expect(await statuses.next() == .unsubscribed)

      try await channel.subscribeWithError()
      #expect(await statuses.next() == .subscribing)
      #expect(await statuses.next() == .subscribed)
    }

    @Test
    func v2StatusMembersKeepWorking() async {
      let channel = fixture.sut.channel("test")
      var clientStatuses = fixture.sut.statusChange.makeAsyncIterator()
      var channelStatuses = channel.statusChange.makeAsyncIterator()

      #expect(await clientStatuses.next() == .disconnected)
      #expect(await channelStatuses.next() == .unsubscribed)

      let received = LockIsolated<[RealtimeClientStatus]>([])
      let subscription = fixture.sut.onStatusChange { status in
        received.withValue { $0.append(status) }
      }
      defer { subscription.cancel() }
      await waitUntil { received.value == [.disconnected] }
      #expect(received.value == [.disconnected])
    }
  }

  @Suite
  struct RealtimeHeartbeatsV3APITests {
    @Test
    func heartbeatsReportsSentAndAcknowledged() async throws {
      let fixture = RealtimeV3Fixture(heartbeatInterval: 0.05)
      fixture.startServer()
      var events = await fixture.sut.heartbeats().makeAsyncIterator()

      await fixture.sut.connect()

      #expect(await events.next() == .sent)
      guard case .acknowledged(let latency)? = await events.next() else {
        Issue.record("expected an acknowledged heartbeat")
        return
      }
      #expect(latency >= .zero)
      #expect(latency < .seconds(5))
    }

    @Test
    func heartbeatsReportsTimedOutWhenTheServerDoesNotAnswer() async throws {
      let fixture = RealtimeV3Fixture(heartbeatInterval: 0.05)
      var events = await fixture.sut.heartbeats().makeAsyncIterator()

      await fixture.sut.connect()

      #expect(await events.next() == .sent)
      #expect(await events.next() == .timedOut)
    }

    @Test
    func v2HeartbeatMembersKeepWorking() async throws {
      let fixture = RealtimeV3Fixture(heartbeatInterval: 0.05)
      fixture.startServer()
      var statuses = fixture.sut.heartbeat.makeAsyncIterator()
      let received = LockIsolated<[HeartbeatStatus]>([])
      let subscription = fixture.sut.onHeartbeat { status in
        received.withValue { $0.append(status) }
      }
      defer { subscription.cancel() }

      await fixture.sut.connect()

      #expect(await statuses.next() == .sent)
      #expect(await statuses.next() == .ok)
      await waitUntil { received.value.count >= 2 }
      #expect(received.value.prefix(2) == [.sent, .ok])
    }
  }

  @Suite
  struct RealtimeBroadcastsV3APITests {
    let fixture = RealtimeV3Fixture()

    private func textBroadcast(
      event: String, payload: JSONObject, meta: JSONObject? = nil
    ) -> RealtimeMessageV2 {
      var body: JSONObject = [
        "type": "broadcast", "event": .string(event), "payload": .object(payload),
      ]
      if let meta { body["meta"] = .object(meta) }
      return RealtimeMessageV2(
        joinRef: nil, ref: nil, topic: "realtime:test", event: "broadcast", payload: body)
    }

    @Test
    func broadcastsUnwrapsATextMessage() async {
      let channel = fixture.sut.channel("test")
      var messages = await channel.broadcasts(event: "cursor").makeAsyncIterator()

      await channel.onMessage(textBroadcast(event: "cursor", payload: ["x": 1]))

      #expect(
        await messages.next() == BroadcastMessage(event: "cursor", payload: .json(["x": 1])))
    }

    @Test
    func broadcastsReadsIdAndReplayedFromMeta() async {
      let id = UUID()
      let channel = fixture.sut.channel("test")
      var messages = await channel.broadcasts(event: "cursor").makeAsyncIterator()

      await channel.onMessage(
        textBroadcast(
          event: "cursor", payload: ["x": 1],
          meta: ["id": .string(id.uuidString), "replayed": true]))

      let message = await messages.next()
      #expect(message?.id == id)
      #expect(message?.isReplayed == true)
    }

    @Test
    func broadcastsMergesJSONAndBinaryFramesInArrivalOrder() async {
      let channel = fixture.sut.channel("test")
      var messages = await channel.broadcasts(event: "frame").makeAsyncIterator()

      await channel.handleBinaryBroadcast(
        DecodedBroadcast(topic: "realtime:test", event: "frame", payload: .binary(Data([1]))))
      await channel.onMessage(textBroadcast(event: "frame", payload: ["n": 2]))
      await channel.handleBinaryBroadcast(
        DecodedBroadcast(topic: "realtime:test", event: "frame", payload: .json(["n": 3])))

      #expect(await messages.next()?.payload == .binary(Data([1])))
      #expect(await messages.next()?.payload == .json(["n": 2]))
      #expect(await messages.next()?.payload == .json(["n": 3]))
    }

    @Test
    func broadcastsReadsTheMetadataOfABinaryFrame() async throws {
      let id = UUID()
      let meta = Data(#"{"id":"\#(id.uuidString)","replayed":true}"#.utf8)
      let topic = Data("realtime:test".utf8)
      let event = Data("frame".utf8)
      var frame = Data([
        RealtimeSerializer.BinaryKind.userBroadcast.rawValue,
        UInt8(topic.count), UInt8(event.count), UInt8(meta.count),
        RealtimeSerializer.PayloadEncoding.binary.rawValue,
      ])
      frame.append(topic)
      frame.append(event)
      frame.append(meta)
      frame.append(Data([9, 9]))

      let channel = fixture.sut.channel("test")
      var messages = await channel.broadcasts(event: "frame").makeAsyncIterator()
      await channel.handleBinaryBroadcast(try RealtimeSerializer().decodeBinary(frame))

      #expect(
        await messages.next()
          == BroadcastMessage(
            event: "frame", payload: .binary(Data([9, 9])), id: id, isReplayed: true))
    }

    @Test
    func broadcastsMatchesEventsTheWayBroadcastStreamDoes() async {
      let channel = fixture.sut.channel("test")
      var exact = await channel.broadcasts(event: "Cursor").makeAsyncIterator()
      var every = await channel.broadcasts(event: "*").makeAsyncIterator()
      var other = await channel.broadcasts(event: "other").makeAsyncIterator()

      await channel.onMessage(textBroadcast(event: "cursor", payload: ["x": 1]))
      await channel.onMessage(textBroadcast(event: "other", payload: ["x": 2]))

      #expect(await exact.next()?.event == "cursor")
      #expect(await every.next()?.event == "cursor")
      #expect(await every.next()?.event == "other")
      #expect(await other.next()?.payload == .json(["x": 2]))
    }

    @Test
    func endingABroadcastsStreamRemovesItsCallback() async {
      let channel = fixture.sut.channel("test")
      let task = Task {
        for await _ in await channel.broadcasts(event: "cursor") {}
      }
      await waitUntil { channel.callbackManager.callbacks.count == 1 }
      #expect(channel.callbackManager.callbacks.count == 1)

      task.cancel()
      await task.value
      #expect(channel.callbackManager.callbacks.isEmpty)
    }

    @Test
    func v2BroadcastStreamsKeepTheirElements() async {
      let channel = fixture.sut.channel("test")
      var envelopes = channel.broadcastStream(event: "frame").makeAsyncIterator()
      var bytes = channel.broadcastDataStream(event: "frame").makeAsyncIterator()
      let received = LockIsolated<[JSONObject]>([])
      let subscription = channel.onBroadcast(event: "frame") { envelope in
        received.withValue { $0.append(envelope) }
      }
      defer { subscription.cancel() }

      await channel.onMessage(
        textBroadcast(event: "frame", payload: ["n": 1], meta: ["replayed": true]))
      await channel.handleBinaryBroadcast(
        DecodedBroadcast(topic: "realtime:test", event: "frame", payload: .binary(Data([7]))))

      let envelope: JSONObject? = await envelopes.next()
      #expect(
        envelope == [
          "type": "broadcast", "event": "frame", "payload": ["n": 1], "meta": ["replayed": true],
        ])
      #expect(received.value == [envelope])
      let data: Data? = await bytes.next()
      #expect(data == Data([7]))
    }
  }

  @Suite
  struct RealtimePostgresChangesV3APITests {
    struct Message: Decodable, Equatable {
      var id: Int
      var body: String
    }

    let fixture = RealtimeV3Fixture()

    private func changeMessage(
      ids: [Int] = [1],
      type: String,
      record: JSONObject? = nil,
      oldRecord: JSONObject? = nil,
      errors: AnyJSON = .null
    ) -> RealtimeMessageV2 {
      var data: JSONObject = [
        "type": .string(type),
        "schema": "public",
        "table": "messages",
        "commit_timestamp": "2026-11-12T10:00:00Z",
        "columns": [["name": "id", "type": "int8"], ["name": "body", "type": "text"]],
        "errors": errors,
      ]
      if let record { data["record"] = .object(record) }
      if let oldRecord { data["old_record"] = .object(oldRecord) }
      return RealtimeMessageV2(
        joinRef: nil, ref: nil, topic: "realtime:test", event: "postgres_changes",
        payload: ["ids": .array(ids.map { .integer($0) }), "data": .object(data)])
    }

    private func serverBinding(
      _ event: PostgresChangeEvent, id: Int = 1
    ) -> PostgresJoinConfig {
      PostgresJoinConfig(event: event, schema: "public", table: "messages", id: id)
    }

    @Test
    func postgresChangesYieldsTheChangeTheServerSent() async throws {
      let channel = fixture.sut.channel("test")
      var changes = await channel.postgresChanges(table: "messages").makeAsyncIterator()
      channel.callbackManager.setServerChanges(changes: [serverBinding(.all)])

      await channel.onMessage(
        changeMessage(
          type: "UPDATE", record: ["id": 1, "body": "new"], oldRecord: ["id": 1],
          errors: ["Error 401: Unauthorized"]))

      let change = try #require(await changes.next())
      #expect(change.kind == .update)
      #expect(change.schema == "public")
      #expect(change.table == "messages")
      #expect(change.commitTimestamp == Date(timeIntervalSince1970: 1_794_477_600))
      #expect(
        change.columns == [
          PostgresColumn(name: "id", type: "int8"), PostgresColumn(name: "body", type: "text"),
        ])
      #expect(change.record == PostgresRow(values: ["id": 1, "body": "new"]))
      #expect(change.oldRecord == PostgresRow(values: ["id": 1]))
      #expect(change.errors == ["Error 401: Unauthorized"])
    }

    @Test
    func postgresChangesLeavesOutTheRowsTheServerDidNotSend() async throws {
      let channel = fixture.sut.channel("test")
      var changes = await channel.postgresChanges(table: "messages").makeAsyncIterator()
      channel.callbackManager.setServerChanges(changes: [serverBinding(.all)])

      await channel.onMessage(changeMessage(type: "INSERT", record: ["id": 1, "body": "a"]))
      await channel.onMessage(changeMessage(type: "DELETE", oldRecord: ["id": 1]))

      let insert = try #require(await changes.next())
      #expect(insert.kind == .insert)
      #expect(insert.oldRecord == nil)
      #expect(insert.errors.isEmpty)
      let delete = try #require(await changes.next())
      #expect(delete.kind == .delete)
      #expect(delete.record == nil)
    }

    @Test
    func postgresChangesAddsItsBindingToTheJoin() async {
      let channel = fixture.sut.channel("test")

      _ = await channel.postgresChanges(
        event: .update, schema: "app", table: "orders", filter: .eq("id", value: 5),
        select: ["id"])
      _ = await channel.postgresChanges()

      let bindings = channel.clientChanges.value
      #expect(bindings.count == 2)
      #expect(bindings[0].event == .update)
      #expect(bindings[0].schema == "app")
      #expect(bindings[0].table == "orders")
      #expect(bindings[0].filter == "id=eq.5")
      #expect(bindings[0].select == ["id"])
      #expect(bindings[1].event == .all)
      #expect(bindings[1].schema == "public")
      #expect(bindings[1].table == nil)
    }

    @Test
    func postgresChangesForOneEventSkipsOtherKinds() async throws {
      let channel = fixture.sut.channel("test")
      var inserts = await channel.postgresChanges(event: .insert, table: "messages")
        .makeAsyncIterator()
      _ = await channel.postgresChanges(table: "messages")
      channel.callbackManager.setServerChanges(changes: [serverBinding(.all)])

      await channel.onMessage(changeMessage(type: "UPDATE", record: ["id": 1, "body": "b"]))
      await channel.onMessage(changeMessage(type: "INSERT", record: ["id": 2, "body": "c"]))

      let change = try #require(await inserts.next())
      #expect(change.kind == .insert)
      #expect(change.record?["id"] == 2)
    }

    @Test
    func typedPostgresChangesDecodesTheRowOnDemand() async throws {
      let channel = fixture.sut.channel("test")
      var changes = await channel.postgresChanges(of: Message.self, table: "messages")
        .makeAsyncIterator()
      channel.callbackManager.setServerChanges(changes: [serverBinding(.all)])

      await channel.onMessage(changeMessage(type: "INSERT", record: ["id": 1, "body": "a"]))
      await channel.onMessage(changeMessage(type: "INSERT", record: ["id": "bad"]))
      await channel.onMessage(changeMessage(type: "DELETE", oldRecord: ["id": 1]))

      let insert = try #require(await changes.next())
      #expect(insert.kind == .insert)
      #expect(insert.raw.table == "messages")
      #expect(try insert.row() == Message(id: 1, body: "a"))

      let undecodable = try #require(await changes.next())
      #expect(throws: RealtimeError.self) { try undecodable.row() }

      let delete = try #require(await changes.next())
      #expect(delete.kind == .delete)
      #expect(delete.oldRecord == PostgresRow(values: ["id": 1]))
      do {
        _ = try delete.row()
        Issue.record("expected row() to throw for a delete")
      } catch let error as RealtimeError {
        #expect(error.kind == .decoding)
      }
    }

    @Test
    func typedPostgresChangesUsesTheGivenDecoder() async throws {
      struct Row: Decodable, Equatable {
        var messageBody: String
      }
      let decoder = JSONDecoder()
      decoder.keyDecodingStrategy = .convertFromSnakeCase
      let channel = fixture.sut.channel("test")
      var changes = await channel.postgresChanges(
        of: Row.self, table: "messages", decoder: decoder
      ).makeAsyncIterator()
      channel.callbackManager.setServerChanges(changes: [serverBinding(.all)])

      await channel.onMessage(changeMessage(type: "INSERT", record: ["message_body": "a"]))

      #expect(try await changes.next()?.row() == Row(messageBody: "a"))
    }

    @Test
    func postgresChangesOpenedAfterSubscribeEndsAtOnce() async throws {
      let channel = try await fixture.subscribedChannel()

      var changes = await channel.postgresChanges(table: "messages").makeAsyncIterator()

      #expect(await changes.next() == nil)
      #expect(channel.clientChanges.value.isEmpty)
    }

    @Test
    func v2PostgresChangeStreamsKeepTheirElements() async throws {
      let channel = fixture.sut.channel("test")
      var inserts = channel.postgresChange(InsertAction.self, table: "messages")
        .makeAsyncIterator()
      var actions = channel.postgresChange(AnyAction.self, table: "messages").makeAsyncIterator()
      var changes = await channel.postgresChanges(table: "messages").makeAsyncIterator()
      let received = LockIsolated<[DeleteAction]>([])
      let subscription = channel.onPostgresChange(DeleteAction.self, table: "messages") {
        action in received.withValue { $0.append(action) }
      }
      defer { subscription.cancel() }
      channel.callbackManager.setServerChanges(changes: [serverBinding(.all)])

      let insertMessage = changeMessage(type: "INSERT", record: ["id": 1, "body": "a"])
      await channel.onMessage(insertMessage)
      await channel.onMessage(changeMessage(type: "DELETE", oldRecord: ["id": 1]))

      let insert = try #require(await inserts.next())
      #expect(insert.record == ["id": 1, "body": "a"])
      #expect(insert.columns.map(\.name) == ["id", "body"])
      #expect(insert.rawMessage == insertMessage)
      #expect(try insert.decodeRecord(as: Message.self, decoder: JSONDecoder()).body == "a")

      guard case .insert(let wrapped)? = await actions.next() else {
        Issue.record("expected an insert action")
        return
      }
      #expect(wrapped == insert)
      guard case .delete(let delete)? = await actions.next() else {
        Issue.record("expected a delete action")
        return
      }
      #expect(delete.oldRecord == ["id": 1])
      #expect(received.value == [delete])
      #expect(await changes.next()?.kind == .insert)
    }
  }

  @Suite
  struct RealtimePresenceV3APITests {
    let fixture = RealtimeV3Fixture()

    private func stateMessage(_ payload: JSONObject) -> RealtimeMessageV2 {
      RealtimeMessageV2(
        joinRef: nil, ref: nil, topic: "realtime:test", event: "presence_state", payload: payload)
    }

    private func diffMessage(joins: JSONObject = [:], leaves: JSONObject = [:])
      -> RealtimeMessageV2
    {
      RealtimeMessageV2(
        joinRef: nil, ref: nil, topic: "realtime:test", event: "presence_diff",
        payload: ["joins": .object(joins), "leaves": .object(leaves)])
    }

    private func metas(_ metas: JSONObject...) -> AnyJSON {
      ["metas": .array(metas.map { .object($0) })]
    }

    @Test
    func presenceChangesYieldsTheStateThenTheDiffs() async throws {
      let channel = fixture.sut.channel("test")
      var changes = await channel.presenceChanges().makeAsyncIterator()

      await channel.onMessage(
        stateMessage([
          "ana": metas(["phx_ref": "r1", "name": "Ana"], ["phx_ref": "r2", "name": "Ana 2"])
        ]))
      await channel.onMessage(
        diffMessage(
          joins: ["ana": metas(["phx_ref": "r3", "phx_ref_prev": "r1", "name": "Ana 3"])],
          leaves: ["ana": metas(["phx_ref": "r1", "name": "Ana"])]))

      let first = try #require(await changes.next())
      #expect(
        first
          == PresenceChange(joins: [
            "ana": [
              PresenceEntry(ref: "r1", payload: ["name": "Ana"]),
              PresenceEntry(ref: "r2", payload: ["name": "Ana 2"]),
            ]
          ]))
      let second = try #require(await changes.next())
      #expect(
        second
          == PresenceChange(
            joins: [
              "ana": [PresenceEntry(ref: "r3", previousRef: "r1", payload: ["name": "Ana 3"])]
            ],
            leaves: ["ana": [PresenceEntry(ref: "r1", payload: ["name": "Ana"])]]))
    }

    @Test
    func presenceStatesYieldsTheCurrentStateThenEachNewState() async throws {
      let channel = fixture.sut.channel("test")
      var states = await channel.presenceStates().makeAsyncIterator()

      #expect(await states.next() == PresenceState())

      await channel.onMessage(stateMessage(["ana": metas(["phx_ref": "r1"])]))
      await channel.onMessage(diffMessage(joins: ["bia": metas(["phx_ref": "r2"])]))

      let ana = PresenceEntry(ref: "r1", payload: [:])
      let bia = PresenceEntry(ref: "r2", payload: [:])
      #expect(await states.next() == PresenceState(entries: ["ana": [ana]]))
      #expect(await states.next() == PresenceState(entries: ["ana": [ana], "bia": [bia]]))
      #expect(await channel.presenceState == PresenceState(entries: ["ana": [ana], "bia": [bia]]))
    }

    @Test
    func aDiffBeforeTheFirstStateWaitsForIt() async throws {
      let channel = fixture.sut.channel("test")
      var changes = await channel.presenceChanges().makeAsyncIterator()

      await channel.onMessage(diffMessage(joins: ["bia": metas(["phx_ref": "r2"])]))
      #expect(await channel.presenceState == PresenceState())
      await channel.onMessage(stateMessage(["ana": metas(["phx_ref": "r1"])]))

      let change = try #require(await changes.next())
      #expect(Set(change.joins.keys) == ["ana", "bia"])
    }

    @Test
    func aPresenceStreamEnablesPresenceOnTheJoin() async throws {
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
      let channel = fixture.sut.channel("test")
      let states = await channel.presenceStates()

      try await channel.subscribeWithError()

      let config = joins.value.first?.payload["config"]?.objectValue
      #expect(config?["presence"]?.objectValue?["enabled"] == true)
      _ = states
    }

    @Test
    func unsubscribeEmptiesTheStateAndReportsTheLeaves() async throws {
      fixture.startServer()
      await fixture.sut.connect()
      let channel = fixture.sut.channel("test")
      var changes = await channel.presenceChanges().makeAsyncIterator()
      try await channel.subscribeWithError()
      await channel.onMessage(stateMessage(["ana": metas(["phx_ref": "r1"])]))
      _ = await changes.next()

      let unsubscribe = Task { await channel.unsubscribe() }
      fixture.server.send(
        RealtimeMessageV2(
          joinRef: nil, ref: nil, topic: "realtime:test", event: "phx_close", payload: [:]))
      await unsubscribe.value

      let change = try #require(await changes.next())
      #expect(change == PresenceChange(leaves: ["ana": [PresenceEntry(ref: "r1", payload: [:])]]))
      #expect(await channel.presenceState == PresenceState())
    }

    @Test
    func presenceStreamsOpenedAfterSubscribeEndAtOnce() async throws {
      let channel = try await fixture.subscribedChannel()

      var changes = await channel.presenceChanges().makeAsyncIterator()
      var states = await channel.presenceStates().makeAsyncIterator()

      #expect(await changes.next() == nil)
      #expect(await states.next() == nil)
    }

    @Test
    @available(*, deprecated, message: "Tests the deprecated v2 presence callback.")
    func theV2CallbackStillReceivesEachMessage() async throws {
      let channel = fixture.sut.channel("test")
      let actions = LockIsolated<[[String: PresenceV2]]>([])
      let subscription = channel.onPresenceChange { action in
        actions.withValue { $0.append(action.joins) }
      }

      await channel.onMessage(diffMessage(joins: ["bia": metas(["phx_ref": "r2", "name": "Bia"])]))
      await channel.onMessage(stateMessage(["ana": metas(["phx_ref": "r1"])]))

      #expect(
        actions.value == [
          ["bia": PresenceV2(ref: "r2", state: ["name": "Bia"])],
          ["ana": PresenceV2(ref: "r1", state: [:])],
        ])
      subscription.cancel()
    }
  }

  @Suite
  struct RealtimeChannelEventsV3APITests {
    let fixture = RealtimeV3Fixture()

    private func systemMessage(extension: String, status: String, message: String)
      -> RealtimeMessageV2
    {
      RealtimeMessageV2(
        joinRef: nil, ref: nil, topic: "realtime:test", event: "system",
        payload: [
          "extension": .string(`extension`), "status": .string(status),
          "message": .string(message), "channel": "test",
        ])
    }

    @Test
    func eventsReportsThePostgresChangesAndReplicationMessages() async throws {
      let channel = fixture.sut.channel("test")
      var events = await channel.events().makeAsyncIterator()

      await channel.onMessage(
        systemMessage(
          extension: "postgres_changes", status: "ok", message: "Subscribed to PostgreSQL"))
      await channel.onMessage(
        systemMessage(extension: "postgres_changes", status: "error", message: "bad filter"))
      await channel.onMessage(
        systemMessage(
          extension: "system", status: "ok", message: "Replication connection established"))
      await channel.onMessage(
        systemMessage(extension: "system", status: "error", message: "not in time"))

      #expect(await events.next() == .postgresChangesReady)
      #expect(await events.next() == .postgresChangesFailed("bad filter"))
      #expect(await events.next() == .replicationReady)
      #expect(await events.next() == .replicationFailed("not in time"))
    }

    @Test
    func eventsReportsARejoinButNotTheFirstJoin() async throws {
      fixture.startServer()
      await fixture.sut.connect()
      let channel = fixture.sut.channel("test")
      var events = await channel.events().makeAsyncIterator()

      try await channel.subscribeWithError()
      try await channel.rejoinAfterReconnect()
      await channel.onMessage(
        systemMessage(
          extension: "system", status: "ok", message: "Replication connection established"))

      #expect(await events.next() == .resubscribed)
      #expect(await events.next() == .replicationReady)
    }

    @Test
    func eventsDoesNotReportASubscribeAfterUnsubscribe() async throws {
      fixture.startServer()
      await fixture.sut.connect()
      let channel = fixture.sut.channel("test")
      var events = await channel.events().makeAsyncIterator()

      try await channel.subscribeWithError()
      let unsubscribe = Task { await channel.unsubscribe() }
      fixture.server.send(
        RealtimeMessageV2(
          joinRef: nil, ref: nil, topic: "realtime:test", event: "phx_close", payload: [:]))
      await unsubscribe.value
      await channel.onMessage(
        systemMessage(
          extension: "system", status: "ok", message: "Replication connection established"))

      #expect(await events.next() == .replicationReady)
    }

    @Test
    @available(*, deprecated, message: "Tests the deprecated v2 system stream.")
    func theV2SystemStreamStillReceivesTheMessage() async throws {
      let channel = fixture.sut.channel("test")
      var messages = channel.system().makeAsyncIterator()
      let message = systemMessage(
        extension: "postgres_changes", status: "ok", message: "Subscribed to PostgreSQL")

      await channel.onMessage(message)

      #expect(await messages.next() == message)
    }
  }
#endif
