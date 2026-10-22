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
  let sut = RealtimeChannel(
    topic: "topic",
    config: RealtimeChannelConfig(
      broadcast: BroadcastJoinConfig(),
      presence: PresenceJoinConfig(),
      isPrivate: false
    ),
    client: RealtimeClient(
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(headers: ["apikey": "test-key"])
    ),
    logger: supabaseDefaultLogger(label: "io.supabase.realtime")
  )

  @Test
  func typedFilterAndSelectAreBufferedIntoPostgresJoinConfig() async {
    let stream = await sut.postgresChanges(
      UpdateAction.self,
      table: "orders",
      filter: .and([
        .gt("amount", value: 100),
        .not(.in("status", values: ["draft"])),
      ]),
      select: ["id", "name"]
    )

    let changes = await sut.clientChanges
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
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        options: RealtimeClientOptions(
          headers: ["apikey": "test-key"],
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
              RealtimeMessageV2(
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

      let listenerCountBefore = await channel.listeners.count

      await withKnownIssue {
        _ = await channel.presenceChanges()
      }

      #expect(await channel.listeners.count == listenerCountBefore)

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
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        options: RealtimeClientOptions(
          headers: ["apikey": "test-key"],
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
              RealtimeMessageV2(
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

      let listenerCountBefore = await channel.listeners.count

      await withKnownIssue {
        _ = await channel.presenceChanges()
      }

      #expect(await channel.listeners.count == listenerCountBefore)

      await socket.disconnect()
    }
  #endif

  #if canImport(Darwin)
    @Test
    @MainActor
    func postgresChangeCallbackRejectedWhileSubscribing() async throws {
      let (client, server) = FakeWebSocket.fakes()
      let socket = RealtimeClient(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        options: RealtimeClientOptions(
          headers: ["apikey": "test-key"],
          accessToken: { "test-token" }
        ),
        wsTransport: { _, _ in client },
        http: HTTPClient(transport: RecordingTransport()),
        clock: ContinuousClock()
      )

      let channel = await socket.channel("test-topic")

      let serverTask3 = Task { @Sendable [server] in
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
          }
        }
      }
      defer { serverTask3.cancel() }

      try await socket.connect()

      let subscribeTask = Task { try? await channel.subscribe() }

      await waitForChannelStatus(.subscribing, channel: channel, timeout: 2.0)
      #expect(await channel.status == .subscribing)

      let listenerCountBefore = await channel.listeners.count

      await withKnownIssue {
        _ = await channel.postgresChanges(AnyAction.self, schema: "public")
      }

      #expect(await channel.listeners.count == listenerCountBefore)

      subscribeTask.cancel()
      await socket.disconnect()
    }
  #endif

  #if canImport(Darwin)
    @Test
    @MainActor
    func postgresChangeCallbackRejectedWhileSubscribed() async throws {
      let (client, server) = FakeWebSocket.fakes()
      let socket = RealtimeClient(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        options: RealtimeClientOptions(
          headers: ["apikey": "test-key"],
          accessToken: { "test-token" }
        ),
        wsTransport: { _, _ in client },
        http: HTTPClient(transport: RecordingTransport()),
        clock: ContinuousClock()
      )

      let channel = await socket.channel("test-topic")

      let serverTask4 = Task { @Sendable [server] in
        for await event in server.events {
          guard let msg = event.realtimeMessage else { continue }
          if msg.event == "phx_join" {
            server.send(
              RealtimeMessageV2(
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
      defer { serverTask4.cancel() }

      try await socket.connect()
      try? await channel.subscribe()
      #expect(await channel.status == .subscribed)

      let listenerCountBefore = await channel.listeners.count

      await withKnownIssue {
        _ = await channel.postgresChanges(AnyAction.self, schema: "public")
      }

      #expect(await channel.listeners.count == listenerCountBefore)

      await socket.disconnect()
    }
  #endif

  @Test
  func attachCallbacks() async {
    let streams: [any Sendable] = [
      await sut.postgresChanges(
        AnyAction.self,
        schema: "public",
        table: "users",
        filter: .eq("id", value: 1)
      ),
      await sut.postgresChanges(InsertAction.self, schema: "private"),
      await sut.postgresChanges(UpdateAction.self, table: "messages"),
      await sut.postgresChanges(DeleteAction.self),
      await sut.broadcasts(event: "test"),
      await sut.broadcasts(event: "cursor-pos"),
      await sut.presenceChanges(),
      await sut.systemMessages(),
    ]

    let kinds = await sut.listeners.map { entry -> String in
      switch entry.listener {
      case .postgres: "postgres"
      case .broadcast(let event, _): "broadcast(\(event))"
      case .broadcastData(let event, _): "broadcastData(\(event))"
      case .presence: "presence"
      case .system: "system"
      case .status: "status"
      }
    }
    #expect(
      kinds == [
        "postgres", "postgres", "postgres", "postgres",
        "broadcast(test)", "broadcast(cursor-pos)",
        "presence", "system",
      ]
    )
    #expect(await sut.hasPresenceListener)

    let clientChanges = await sut.clientChanges
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
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: RecordingTransport()),
      clock: ContinuousClock()
    )

    // Create a channel without a presence stream initially
    let channel = await socket.channel("test-topic")

    #expect(!channel.config.presence.enabled)

    try await socket.connect()

    // Open a presence stream before subscribing
    let presence = await channel.presenceChanges()

    // Verify that the presence listener exists
    #expect(await channel.hasPresenceListener)

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
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(headers: ["apikey": "test-key"]),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )

    let channel = await socket.channel("test-topic")

    do {
      try await channel.httpSend(event: "test", message: ["data": "test"])
      Issue.record("Expected httpSend to throw an error when access token is missing")
    } catch {
      #expect((error as? RealtimeError)?.kind == .accessTokenMissing)
      #expect(error.localizedDescription == "Access token is required for httpSend()")
    }
  }

  @Test
  func httpSendThrowsCancellationErrorWhenTheTaskIsCancelled() async {
    let (requestStarted, onRequestStarted) = AsyncStream<Void>.makeStream()
    let httpClient = RecordingTransport { _, _ in
      onRequestStarted.yield()
      try? await Task.sleep(for: .seconds(10))
      throw URLError(.cancelled)
    }
    let (client, _) = FakeWebSocket.fakes()

    let socket = RealtimeClient(
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )
    let channel = await socket.channel("test-topic")

    let task = Task { try await channel.httpSend(event: "test", message: ["data": "test"]) }
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
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"],
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
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )

    let channel = await socket.channel("test-topic") { config in
      config.isPrivate = true
    }

    try await channel.httpSend(event: "test-event", message: ["data": "explicit"])

    let requests = httpClient.requests
    #expect(requests.count == 1)

    let request = requests[0]
    #expect(
      request.head.url?.absoluteString
        == "https://localhost:54321/realtime/v1/api/broadcast/test-topic/events/test-event?private=true"
    )
    #expect(request.head.method == .post)
    #expect(request.head.headerFields[.authorization] == "Bearer test-token")
    #expect(request.head.headerFields[.apiKey] == "test-key")
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
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )

    let channel = await socket.channel("room/one")

    try await channel.httpSend(event: "cursor move", message: ["x": 1])

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
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"],
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
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(headers: ["apikey": "test-key"]),
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
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )

    let channel = await socket.channel("test-topic")

    do {
      try await channel.httpSend(event: "test", message: ["data": "test"])
      Issue.record("Expected httpSend to throw an error on non-202 status")
    } catch let error as RealtimeError {
      #expect(error.kind == .server)
      #expect(error.message == "Server error")
      #expect(error.response?.statusCode == 500)
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
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"], accessToken: { "test-token" }),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )
    let channel = await socket.channel("test-topic")

    do {
      try await channel.httpSend(event: "test", message: ["data": "test"])
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
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"], accessToken: { "test-token" }),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )
    let channel = await socket.channel("test-topic")

    await #expect(throws: CancellationError.self) {
      try await channel.httpSend(event: "test", message: ["data": "test"])
    }
  }

  private struct FetchError: Error {}

  @Test
  func httpSendDoesNotWrapCustomFetchError() async {
    let httpClient = RecordingTransport()
    httpClient.respond { _, _ in throw FetchError() }
    let (client, _) = FakeWebSocket.fakes()
    let socket = RealtimeClient(
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"], accessToken: { "test-token" }),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )
    let channel = await socket.channel("test-topic")

    await #expect(throws: FetchError.self) {
      try await channel.httpSend(event: "test", message: ["data": "test"])
    }
  }

  @Test
  func httpSendRespectsCustomTimeout() async throws {
    let httpClient = RecordingTransport()
    httpClient.respond { _, _ in
      (HTTPResponse(status: .init(code: 202)), Data())
    }
    let (client, _) = FakeWebSocket.fakes()

    let socket = RealtimeClient(
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"],
        timeout: .seconds(5),
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )

    let channel = await socket.channel("test-topic")

    try await channel.httpSend(event: "test", message: ["data": "test"], timeout: .seconds(3))

    let requests = httpClient.requests
    #expect(requests.count == 1)
  }

  @Test
  func httpSendUsesDefaultTimeoutWhenNotSpecified() async throws {
    let httpClient = RecordingTransport()
    httpClient.respond { _, _ in
      (HTTPResponse(status: .init(code: 202)), Data())
    }
    let (client, _) = FakeWebSocket.fakes()

    let socket = RealtimeClient(
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"],
        timeout: .seconds(5),
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )

    let channel = await socket.channel("test-topic")

    try await channel.httpSend(event: "test", message: ["data": "test"])

    let requests = httpClient.requests
    #expect(requests.count == 1)
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
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )

    let channel = await socket.channel("test-topic")

    do {
      try await channel.httpSend(event: "test", message: ["data": "test"])
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
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: httpClient),
      clock: ContinuousClock()
    )

    let channel = await socket.channel("test-topic")

    do {
      try await channel.httpSend(event: "test", message: ["data": "test"])
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
    func channelErrorResetsSubscribedStatus() async throws {
      let (client, server) = FakeWebSocket.fakes()
      let socket = RealtimeClient(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        options: RealtimeClientOptions(
          headers: ["apikey": "test-key"],
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
              RealtimeMessageV2(
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

      server.send(
        RealtimeMessageV2(
          joinRef: nil,
          ref: nil,
          topic: "realtime:test-topic",
          event: "phx_error",
          payload: [:]
        )
      )

      await waitForChannelStatus(.unsubscribed, channel: channel, timeout: 2.0)
      #expect(await channel.status == .unsubscribed)

      await socket.disconnect()
    }
  #endif
}

extension RealtimeChannelTests {
  private func waitForChannelStatus(
    _ status: RealtimeChannelStatus,
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
    timeout: TimeInterval,
    pollInterval: UInt64 = 10_000_000
  ) async -> [RealtimeMessageV2] {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
      let events = socket.receivedEvents.compactMap { $0.realtimeMessage }.filter {
        $0.event == event
      }

      if !events.isEmpty {
        return events
      }

      try? await Task.sleep(nanoseconds: pollInterval)
    }

    return []
  }
}
