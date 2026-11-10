//
//  RealtimeChannelTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 09/09/24.
//
import ConcurrencyExtras
import Foundation
import HTTPTypes
import InlineSnapshotTesting
import Logging
import TestHelpers
import Testing
@testable import Realtime

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct RealtimeChannelTests {
  let client: RealtimeClient
  let sut: RealtimeChannel

  init() async throws {
    client = try RealtimeClient(
      configuration: RealtimeClient.Configuration(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        headers: [.apikey: "test-key"])
    )
    sut = await client.channel("topic")
  }

  @Test
  func statusIsUnsubscribedBeforeTheFirstSubscribe() async {
    let status: RealtimeChannelStatus = await sut.status
    #expect(status.isSame(as: .unsubscribed))
  }

  @Test
  func typedFilterAndSelectAreBufferedIntoPostgresJoinConfig() async {
    let stream = await sut.postgresChanges(
      event: .update,
      table: "orders",
      filter: .and([
        .gt("amount", value: 100),
        .not(.in("status", values: ["draft"])),
      ]),
      select: ["id", "name"]
    )

    let changes = await client.bindings(of: sut)
    #expect(changes.count == 1)
    #expect(changes.first?.event == .update)
    #expect(changes.first?.table == "orders")
    #expect(changes.first?.filter == "amount=gt.100,status=not.in.(draft)")
    #expect(changes.first?.select == ["id", "name"])
    withExtendedLifetime(stream) {}
  }

  // MARK: - Stream rejection tests

  #if canImport(Darwin)
    @Test
    @MainActor
    func presenceChangeCallbackRejectedWhileSubscribing() async throws {
      let (client, server) = FakeWebSocket.fakes()
      let socket = RealtimeClient(
        configuration: RealtimeClient.Configuration(
          url: URL(string: "https://localhost:54321/realtime/v1")!,
          headers: [.apikey: "test-key"],
          accessToken: { "test-token" }
        ),
        wsTransport: { _, _ in client },
        http: HTTPClient(transport: RecordingTransport()),
        clock: ContinuousClock()
      )

      let channel = await socket.channel("test-topic")

      let serverTask1 = Task { @Sendable [server] in
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
          }
        }
      }
      defer { serverTask1.cancel() }

      try await socket.connect()

      let subscribeTask = Task { try? await channel.subscribe() }

      await waitForChannelStatus(.subscribing, channel: channel, timeout: 2.0)
      #expect(await channel.status == .subscribing)

      let listenerCountBefore = await socket.streamCounts(of: channel).presenceChanges

      await withKnownIssue {
        _ = await channel.presenceChanges()
      }

      #expect(await socket.streamCounts(of: channel).presenceChanges == listenerCountBefore)

      subscribeTask.cancel()
      await socket.disconnect()
    }
  #endif

  #if canImport(Darwin)
    @Test
    @MainActor
    func presenceChangeCallbackRejectedWhileSubscribed() async throws {
      let (client, server) = FakeWebSocket.fakes()
      let socket = RealtimeClient(
        configuration: RealtimeClient.Configuration(
          url: URL(string: "https://localhost:54321/realtime/v1")!,
          headers: [.apikey: "test-key"],
          accessToken: { "test-token" }
        ),
        wsTransport: { _, _ in client },
        http: HTTPClient(transport: RecordingTransport()),
        clock: ContinuousClock()
      )

      let channel = await socket.channel("test-topic")

      let serverTask2 = Task { @Sendable [server] in
        for await event in server.events {
          guard let msg = event.realtimeMessage else { continue }
          if msg.event == "phx_join" {
            server.send(
              RealtimeMessage(
                joinRef: msg.joinRef,
                ref: msg.ref,
                topic: "realtime:test-topic",
                event: "phx_reply",
                payload: [
                  "response": ["postgres_changes": []],
                  "status": "ok",
                ]
              )
            )
          }
        }
      }
      defer { serverTask2.cancel() }

      try await socket.connect()
      try? await channel.subscribe()
      #expect(await channel.status == .subscribed)

      let listenerCountBefore = await socket.streamCounts(of: channel).presenceChanges

      await withKnownIssue {
        _ = await channel.presenceChanges()
      }

      #expect(await socket.streamCounts(of: channel).presenceChanges == listenerCountBefore)

      await socket.disconnect()
    }
  #endif

  @Test
  func attachCallbacks() async {
    let streams: [any Sendable] = await [
      await sut.postgresChanges(
        schema: "public",
        table: "users",
        filter: .eq("id", value: 1)
      ),
      sut.postgresChanges(event: .insert, schema: "private"),
      sut.postgresChanges(event: .update, table: "messages"),
      sut.postgresChanges(event: .delete),
      sut.broadcasts(event: "test"),
      sut.broadcasts(event: "cursor-pos"),
      sut.presenceChanges(),
      sut.presenceStates(),
      sut.events(),
    ]

    #expect(
      await client.streamCounts(of: sut)
        == RealtimeClient.StreamCounts(
          events: 1, broadcasts: 2, presenceChanges: 1, presenceStates: 1, postgres: 4))
    #expect(await client.hasPresenceListener(sut))

    let clientChanges = await client.bindings(of: sut)
    assertInlineSnapshot(of: clientChanges, as: .dump) {
      """
      ▿ 4 elements
        ▿ PostgresJoinConfig
          ▿ event: Optional<PostgresChangeEvent>
            - some: PostgresChangeEvent.all
          ▿ filter: Optional<String>
            - some: "id=eq.1"
          - id: 0
          - schema: "public"
          - select: Optional<Array<String>>.none
          ▿ table: Optional<String>
            - some: "users"
        ▿ PostgresJoinConfig
          ▿ event: Optional<PostgresChangeEvent>
            - some: PostgresChangeEvent.insert
          - filter: Optional<String>.none
          - id: 0
          - schema: "private"
          - select: Optional<Array<String>>.none
          - table: Optional<String>.none
        ▿ PostgresJoinConfig
          ▿ event: Optional<PostgresChangeEvent>
            - some: PostgresChangeEvent.update
          - filter: Optional<String>.none
          - id: 0
          - schema: "public"
          - select: Optional<Array<String>>.none
          ▿ table: Optional<String>
            - some: "messages"
        ▿ PostgresJoinConfig
          ▿ event: Optional<PostgresChangeEvent>
            - some: PostgresChangeEvent.delete
          - filter: Optional<String>.none
          - id: 0
          - schema: "public"
          - select: Optional<Array<String>>.none
          - table: Optional<String>.none

      """
    }
    withExtendedLifetime(streams) {}
  }

  @Test
  @MainActor
  func presenceEnabledDuringSubscribe() async throws {
    let (client, server) = FakeWebSocket.fakes()

    let socket = RealtimeClient(
      configuration: RealtimeClient.Configuration(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        headers: [.apikey: "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: RecordingTransport()),
      clock: ContinuousClock()
    )

    // Create a channel without a presence stream initially
    let channel = await socket.channel("test-topic")

    try await socket.connect()

    // Open a presence stream before subscribing
    let presence = await channel.presenceChanges()

    // Verify that the presence listener exists
    #expect(await socket.hasPresenceListener(channel))

    Task {
      try? await channel.subscribe()
    }

    let joinEvents = await waitForEvents(
      in: server,
      event: "phx_join",
      timeout: 1.0
    )

    #expect(joinEvents.count > 0)

    if let joinEvent = joinEvents.first,
      let config = joinEvent.payload["config"]?.objectValue,
      let presence = config["presence"]?.objectValue,
      let enabled = presence["enabled"]?.boolValue
    {
      #expect(enabled, "Presence should be enabled when a presence stream is open")
    } else {
      Issue.record("Could not find presence enabled flag in join payload")
    }

    withExtendedLifetime(presence) {}
    await channel.unsubscribe()
    await socket.disconnect()

  }

  @Test
  func httpSendThrowsWhenAccessTokenIsMissing() async {
    let httpClient = RecordingTransport()
    let (client, _) = FakeWebSocket.fakes()

    let socket = RealtimeClient(
      configuration: RealtimeClient.Configuration(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        headers: [.apikey: "test-key"]),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )

    let channel = await socket.channel("test-topic")

    do {
      try await channel.httpSend(event: "test", payload: ["data": "test"])
      Issue.record("Expected httpSend to throw an error when access token is missing")
    } catch {
      #expect((error as? RealtimeError)?.kind == .accessTokenMissing)
      #expect(error.localizedDescription == "Access token is required for httpSend()")
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func httpSendThrowsCancellationErrorWhenTheTaskIsCancelled() async {
    let (requestStarted, onRequestStarted) = AsyncStream<Void>.makeStream()
    let httpClient = RecordingTransport { _, _ in
      onRequestStarted.yield()
      await Gate().pass()
      throw URLError(.cancelled)
    }
    let (client, _) = FakeWebSocket.fakes()

    let socket = RealtimeClient(
      configuration: RealtimeClient.Configuration(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        headers: [.apikey: "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )
    let channel = await socket.channel("test-topic")

    let task = Task { try await channel.httpSend(event: "test", payload: ["data": "test"]) }
    for await _ in requestStarted { break }
    task.cancel()

    do {
      try await task.value
      Issue.record("Expected failure")
    } catch is CancellationError {
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test
  func httpSendWrapsCancelledURLErrorWithoutTaskCancellation() async {
    let httpClient = RecordingTransport { _, _ in throw URLError(.cancelled) }
    let (client, _) = FakeWebSocket.fakes()

    let socket = RealtimeClient(
      configuration: RealtimeClient.Configuration(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        headers: [.apikey: "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )
    let channel = await socket.channel("test-topic")

    do {
      try await channel.httpSend(event: "test", data: Data())
      Issue.record("Expected failure")
    } catch let error as RealtimeError {
      #expect(error.kind == .transport)
      #expect((error.underlyingError as? URLError)?.code == .cancelled)
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test
  func httpSendSucceedsOn202Status() async throws {
    let httpClient = RecordingTransport()
    httpClient.respond { _, _ in
      (HTTPResponse(status: .init(code: 202)), Data())
    }
    let (client, _) = FakeWebSocket.fakes()

    let socket = RealtimeClient(
      configuration: RealtimeClient.Configuration(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        headers: [.apikey: "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )

    let channel = await socket.channel("test-topic") { config in
      config.isPrivate = true
    }

    try await channel.httpSend(event: "test-event", payload: ["data": "explicit"])

    let requests = httpClient.requests
    #expect(requests.count == 1)

    let request = requests[0]
    #expect(
      request.head.url?.absoluteString
        == "https://localhost:54321/realtime/v1/api/broadcast/test-topic/events/test-event?private=true"
    )
    #expect(request.head.method == .post)
    #expect(request.head.headerFields[.authorization] == "Bearer test-token")
    #expect(request.head.headerFields[.apikey] == "test-key")
    #expect(request.head.headerFields[.contentType] == "application/json")

    let body = try JSONDecoder().decode([String: String].self, from: request.body ?? Data())
    #expect(body == ["data": "explicit"])
  }

  @Test
  func httpSendPercentEncodesTopicAndEventInURL() async throws {
    let httpClient = RecordingTransport()
    httpClient.respond { _, _ in
      (HTTPResponse(status: .init(code: 202)), Data())
    }
    let (client, _) = FakeWebSocket.fakes()

    let socket = RealtimeClient(
      configuration: RealtimeClient.Configuration(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        headers: [.apikey: "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )

    let channel = await socket.channel("room/one")

    try await channel.httpSend(event: "cursor move", payload: ["x": 1])

    let requests = httpClient.requests
    #expect(
      requests[0].head.url?.absoluteString
        == "https://localhost:54321/realtime/v1/api/broadcast/room%2Fone/events/cursor%20move"
    )
  }

  @Test
  func httpSendWithBinaryDataSendsOctetStream() async throws {
    let httpClient = RecordingTransport()
    httpClient.respond { _, _ in
      (HTTPResponse(status: .init(code: 202)), Data())
    }
    let (client, _) = FakeWebSocket.fakes()

    let socket = RealtimeClient(
      configuration: RealtimeClient.Configuration(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        headers: [.apikey: "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )

    let channel = await socket.channel("test-topic")

    let payload = Data([0x01, 0x02, 0x03])
    try await channel.httpSend(event: "binary-event", data: payload)

    let requests = httpClient.requests
    #expect(requests.count == 1)

    let request = requests[0]
    #expect(
      request.head.url?.absoluteString
        == "https://localhost:54321/realtime/v1/api/broadcast/test-topic/events/binary-event"
    )
    #expect(request.head.headerFields[.contentType] == "application/octet-stream")
    #expect(request.body == payload)
  }

  @Test
  func httpSendWithBinaryDataThrowsWhenAccessTokenIsMissing() async {
    let httpClient = RecordingTransport()
    let (client, _) = FakeWebSocket.fakes()

    let socket = RealtimeClient(
      configuration: RealtimeClient.Configuration(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        headers: [.apikey: "test-key"]),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )

    let channel = await socket.channel("test-topic")

    do {
      try await channel.httpSend(event: "test", data: Data([0x01]))
      Issue.record("Expected httpSend to throw an error when access token is missing")
    } catch {
      #expect((error as? RealtimeError)?.kind == .accessTokenMissing)
      #expect(error.localizedDescription == "Access token is required for httpSend()")
    }
  }

  @Test
  func httpSendThrowsOnNon202Status() async {
    let httpClient = RecordingTransport()
    httpClient.respond { _, _ in
      let errorBody = try JSONEncoder().encode(["error": "Server error"])
      return (HTTPResponse(status: .init(code: 500)), errorBody)
    }
    let (client, _) = FakeWebSocket.fakes()

    let socket = RealtimeClient(
      configuration: RealtimeClient.Configuration(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        headers: [.apikey: "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )

    let channel = await socket.channel("test-topic")

    do {
      try await channel.httpSend(event: "test", payload: ["data": "test"])
      Issue.record("Expected httpSend to throw an error on non-202 status")
    } catch let error as RealtimeError {
      #expect(error.kind == .server)
      #expect(error.message == "Server error")
      #expect(error.response?.status == 500)
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test
  func httpSendWrapsTransportFailure() async {
    let httpClient = RecordingTransport()
    httpClient.respond { _, _ in throw URLError(.timedOut) }
    let (client, _) = FakeWebSocket.fakes()
    let socket = RealtimeClient(
      configuration: RealtimeClient.Configuration(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        headers: [.apikey: "test-key"],
        accessToken: { "test-token" }),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )
    let channel = await socket.channel("test-topic")

    do {
      try await channel.httpSend(event: "test", payload: ["data": "test"])
      Issue.record("Expected failure")
    } catch let error as RealtimeError {
      #expect(error.kind == .transport)
      #expect((error.underlyingError as? URLError)?.code == .timedOut)
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test
  func httpSendDoesNotWrapCancellation() async {
    let httpClient = RecordingTransport()
    httpClient.respond { _, _ in throw CancellationError() }
    let (client, _) = FakeWebSocket.fakes()
    let socket = RealtimeClient(
      configuration: RealtimeClient.Configuration(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        headers: [.apikey: "test-key"],
        accessToken: { "test-token" }),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )
    let channel = await socket.channel("test-topic")

    await #expect(throws: CancellationError.self) {
      try await channel.httpSend(event: "test", payload: ["data": "test"])
    }
  }

  private struct FetchError: Error {}

  @Test
  func httpSendDoesNotWrapCustomFetchError() async {
    let httpClient = RecordingTransport()
    httpClient.respond { _, _ in throw FetchError() }
    let (client, _) = FakeWebSocket.fakes()
    let socket = RealtimeClient(
      configuration: RealtimeClient.Configuration(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        headers: [.apikey: "test-key"],
        accessToken: { "test-token" }),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )
    let channel = await socket.channel("test-topic")

    await #expect(throws: FetchError.self) {
      try await channel.httpSend(event: "test", payload: ["data": "test"])
    }
  }

  @Test
  func httpSendKeepsTheHTTPClientIdleTimeoutForTheRequest() async throws {
    let seen = LockIsolated<[Duration?]>([])
    let httpClient = RecordingTransport()
    httpClient.respond { _, _ in
      seen.withValue { $0.append(RequestTimeout.current) }
      return (HTTPResponse(status: .init(code: 202)), Data())
    }
    let (client, _) = FakeWebSocket.fakes()
    let socket = RealtimeClient(
      configuration: RealtimeClient.Configuration(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        headers: [.apikey: "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient, timeout: .seconds(42)),
      clock: ContinuousClock()
    )
    let channel = await socket.channel("test-topic")

    try await channel.httpSend(event: "test", payload: ["data": "test"], timeout: .seconds(3))

    #expect(seen.value == [.seconds(42)])
  }

  @Test(arguments: [
    (requestTimeout: Duration.milliseconds(50), callTimeout: Duration?.none),
    (requestTimeout: Duration.seconds(30), callTimeout: Duration?.some(.milliseconds(50))),
  ])
  func httpSendThatRunsPastItsDeadlineTimesOut(
    requestTimeout: Duration, callTimeout: Duration?
  ) async {
    let httpClient = RecordingTransport()
    httpClient.respond { _, _ in
      try await Task.sleep(for: .seconds(30))
      return (HTTPResponse(status: .init(code: 202)), Data())
    }
    let (client, _) = FakeWebSocket.fakes()
    let socket = RealtimeClient(
      configuration: RealtimeClient.Configuration(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        // A static token: a token callback would also be bounded by `requestTimeout`.
        headers: [.apikey: "test-key", .authorization: "Bearer test-token"],
        requestTimeout: requestTimeout
      ),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )
    let channel = await socket.channel("test-topic")

    let error = await #expect(throws: RealtimeError.self) {
      try await channel.httpSend(event: "test", payload: ["data": "test"], timeout: callTimeout)
    }
    #expect(error?.kind == .timeout)
  }

  @Test
  func httpSendStartsFromTheClientHeaders() async throws {
    let httpClient = RecordingTransport()
    httpClient.respond { _, _ in (HTTPResponse(status: .init(code: 202)), Data()) }
    let (client, _) = FakeWebSocket.fakes()
    let socket = RealtimeClient(
      configuration: RealtimeClient.Configuration(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        headers: [
          .apikey: "test-key",
          HTTPField.Name("X-Custom")!: "custom",
          .authorization: "Bearer static-key",
          .contentType: "text/plain",
        ],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )
    let channel = await socket.channel("test-topic")

    try await channel.httpSend(event: "test", data: Data([0x01]))

    let headers = try #require(httpClient.requests.first).head.headerFields
    #expect(headers[.xClientInfo] == RealtimeClient.defaultHeaders[.xClientInfo])
    #expect(headers[.xClientInfo]?.hasPrefix("realtime-swift/") == true)
    #expect(headers[HTTPField.Name("X-Custom")!] == "custom")
    #expect(headers[.apikey] == "test-key")
    #expect(headers[.authorization] == "Bearer test-token")
    #expect(headers[.contentType] == "application/octet-stream")
    #expect(headers[values: .authorization].count == 1)
    #expect(headers[values: .contentType].count == 1)
  }

  @Test
  func httpSendKeepsAnXClientInfoTheAppSets() async throws {
    let httpClient = RecordingTransport()
    httpClient.respond { _, _ in (HTTPResponse(status: .init(code: 202)), Data()) }
    let (client, _) = FakeWebSocket.fakes()
    let socket = RealtimeClient(
      configuration: RealtimeClient.Configuration(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        headers: [.apikey: "test-key", .xClientInfo: "supabase-swift/9.9.9"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )
    let channel = await socket.channel("test-topic")

    try await channel.httpSend(event: "test", payload: ["data": "test"])

    let headers = try #require(httpClient.requests.first).head.headerFields
    #expect(headers[values: .xClientInfo] == ["supabase-swift/9.9.9"])
  }

  @Test
  func httpSendDoesNotRetry() async {
    let httpClient = RecordingTransport()
    httpClient.respond { _, _ in (HTTPResponse(status: .init(code: 503)), Data()) }
    let (client, _) = FakeWebSocket.fakes()
    let socket = RealtimeClient(
      configuration: RealtimeClient.Configuration(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        headers: [.apikey: "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )
    let channel = await socket.channel("test-topic")

    await #expect(throws: RealtimeError.self) {
      try await channel.httpSend(event: "test", payload: ["data": "test"])
    }
    #expect(httpClient.requests.count == 1)
  }

  @Test
  func httpSendFallsBackToStatusTextWhenErrorBodyHasNoErrorField() async {
    let httpClient = RecordingTransport()
    httpClient.respond { _, _ in
      let errorBody = try JSONEncoder().encode(["message": "Invalid request"])
      return (HTTPResponse(status: .init(code: 400)), errorBody)
    }
    let (client, _) = FakeWebSocket.fakes()

    let socket = RealtimeClient(
      configuration: RealtimeClient.Configuration(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        headers: [.apikey: "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )

    let channel = await socket.channel("test-topic")

    do {
      try await channel.httpSend(event: "test", payload: ["data": "test"])
      Issue.record("Expected httpSend to throw an error on 400 status")
    } catch {
      #expect(error.localizedDescription == "Invalid request")
    }
  }

  @Test
  func httpSendFallsBackToStatusTextWhenJSONParsingFails() async {
    let httpClient = RecordingTransport()
    httpClient.respond { _, _ in
      (HTTPResponse(status: .init(code: 503)), Data("Invalid JSON".utf8))
    }
    let (client, _) = FakeWebSocket.fakes()

    let socket = RealtimeClient(
      configuration: RealtimeClient.Configuration(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        headers: [.apikey: "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )

    let channel = await socket.channel("test-topic")

    do {
      try await channel.httpSend(event: "test", payload: ["data": "test"])
      Issue.record("Expected httpSend to throw an error on 503 status")
    } catch {
      let description = error.localizedDescription.lowercased()
      #expect(
        description.contains("503") || description.contains("unavailable"),
        "Expected status text fallback, got '\(error.localizedDescription)'"
      )
    }
  }

  #if canImport(Darwin)
    @Test
    @MainActor
    func channelErrorWaitsToRejoin() async throws {
      let (client, server) = FakeWebSocket.fakes()
      let socket = RealtimeClient(
        configuration: RealtimeClient.Configuration(
          url: URL(string: "https://localhost:54321/realtime/v1")!,
          headers: [.apikey: "test-key"],
          accessToken: { "test-token" }
        ),
        wsTransport: { _, _ in client },
        http: HTTPClient(transport: RecordingTransport()),
        clock: ContinuousClock()
      )

      let channel = await socket.channel("test-topic")

      let serverTask = Task { @Sendable [server] in
        for await event in server.events {
          guard let msg = event.realtimeMessage else { continue }
          if msg.event == "phx_join" {
            server.send(
              RealtimeMessage(
                joinRef: msg.joinRef,
                ref: msg.ref,
                topic: "realtime:test-topic",
                event: "phx_reply",
                payload: [
                  "response": ["postgres_changes": []],
                  "status": "ok",
                ]
              )
            )
          }
        }
      }
      defer { serverTask.cancel() }

      try await socket.connect()
      try? await channel.subscribe()
      #expect(await channel.status == .subscribed)
      // The rejoin runs on the real clock, so read the status stream: it keeps every change.
      let sawRejoinWait = LockIsolated(false)
      let statuses = await channel.statusChanges()
      let watcher = Task {
        for await status in statuses where status == .resubscribing {
          sawRejoinWait.setValue(true)
          return
        }
      }
      defer { watcher.cancel() }

      server.send(
        RealtimeMessage(
          joinRef: nil,
          ref: nil,
          topic: "realtime:test-topic",
          event: "phx_error",
          payload: [:]
        )
      )

      await waitUntil(timeout: 2) { sawRejoinWait.value }
      #expect(sawRejoinWait.value)

      await socket.disconnect()
    }
  #endif
}

extension RealtimeChannelTests {
  private func waitForChannelStatus(
    _ status: ChannelStatusCase,
    channel: RealtimeChannel,
    timeout: TimeInterval,
    pollInterval: UInt64 = 10_000_000
  ) async {
    await waitUntil(timeout: timeout, pollInterval: pollInterval) {
      await channel.status == status
    }
  }

  private func waitForEvents(
    in socket: FakeWebSocket,
    event: String,
    timeout: TimeInterval
  ) async -> [RealtimeMessage] {
    @Sendable func events() -> [RealtimeMessage] {
      socket.receivedEvents.compactMap { $0.realtimeMessage }.filter { $0.event == event }
    }
    await waitUntil(timeout: timeout) { !events().isEmpty }
    return events()
  }
}
