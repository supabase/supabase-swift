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
import TestHelpers
import Testing

@testable import Realtime
@testable import RealtimeV2

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct RealtimeChannelTests {
  let sut = RealtimeChannelV2(
    topic: "topic",
    config: RealtimeChannelConfig(
      broadcast: BroadcastJoinConfig(),
      presence: PresenceJoinConfig(),
      isPrivate: false
    ),
    socket: RealtimeClientV2(
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(headers: ["apikey": "test-key"])
    ),
    logger: nil
  )

  @Test
  func typedFilterAndSelectAreBufferedIntoPostgresJoinConfig() {
    let subscription = sut.onPostgresChange(
      UpdateAction.self,
      table: "orders",
      filter: .and([
        .gt("amount", value: 100),
        .not(.in("status", values: ["draft"])),
      ]),
      select: ["id", "name"]
    ) { _ in }
    defer { subscription.cancel() }

    let changes = sut.clientChanges.value
    #expect(changes.count == 1)
    #expect(changes.first?.event == .update)
    #expect(changes.first?.table == "orders")
    #expect(changes.first?.filter == "amount=gt.100,status=not.in.(draft)")
    #expect(changes.first?.select == ["id", "name"])
  }

  // MARK: - Callback rejection tests

  #if canImport(Darwin)
    @Test
    @MainActor
    func presenceChangeCallbackRejectedWhileSubscribing() async {
      let (client, server) = FakeWebSocket.fakes()
      let socket = RealtimeClientV2(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        options: RealtimeClientOptions(
          headers: ["apikey": "test-key"],
          accessToken: { "test-token" }
        ),
        wsTransport: { _, _ in client },
        http: HTTPClientMock(),
        clock: ContinuousClock()
      )

      let channel = socket.channel("test-topic")

      // Never respond to phx_join, so channel stays in .subscribing
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

      await socket.connect()

      let subscribeTask = Task { try? await channel.subscribeWithError() }

      await waitForChannelStatus(.subscribing, channel: channel, timeout: 2.0)
      #expect(channel.status == .subscribing)

      let callbackCountBefore = channel.callbackManager.callbacks.count

      _ = channel.onPresenceChange { _ in }

      #expect(channel.callbackManager.callbacks.count == callbackCountBefore)

      subscribeTask.cancel()
      socket.disconnect()
    }
  #endif

  #if canImport(Darwin)
    @Test
    @MainActor
    func presenceChangeCallbackRejectedWhileSubscribed() async {
      let (client, server) = FakeWebSocket.fakes()
      let socket = RealtimeClientV2(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        options: RealtimeClientOptions(
          headers: ["apikey": "test-key"],
          accessToken: { "test-token" }
        ),
        wsTransport: { _, _ in client },
        http: HTTPClientMock(),
        clock: ContinuousClock()
      )

      let channel = socket.channel("test-topic")

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

      await socket.connect()
      try? await channel.subscribeWithError()
      #expect(channel.status == .subscribed)

      let callbackCountBefore = channel.callbackManager.callbacks.count

      _ = channel.onPresenceChange { _ in }

      #expect(channel.callbackManager.callbacks.count == callbackCountBefore)

      socket.disconnect()
    }
  #endif

  #if canImport(Darwin)
    @Test
    @MainActor
    func postgresChangeCallbackRejectedWhileSubscribing() async {
      let (client, server) = FakeWebSocket.fakes()
      let socket = RealtimeClientV2(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        options: RealtimeClientOptions(
          headers: ["apikey": "test-key"],
          accessToken: { "test-token" }
        ),
        wsTransport: { _, _ in client },
        http: HTTPClientMock(),
        clock: ContinuousClock()
      )

      let channel = socket.channel("test-topic")

      // Never respond to phx_join, so channel stays in .subscribing
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

      await socket.connect()

      let subscribeTask = Task { try? await channel.subscribeWithError() }

      await waitForChannelStatus(.subscribing, channel: channel, timeout: 2.0)
      #expect(channel.status == .subscribing)

      let callbackCountBefore = channel.callbackManager.callbacks.count

      _ = channel.onPostgresChange(AnyAction.self, schema: "public") { _ in }

      #expect(channel.callbackManager.callbacks.count == callbackCountBefore)

      subscribeTask.cancel()
      socket.disconnect()
    }
  #endif

  #if canImport(Darwin)
    @Test
    @MainActor
    func postgresChangeCallbackRejectedWhileSubscribed() async {
      let (client, server) = FakeWebSocket.fakes()
      let socket = RealtimeClientV2(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        options: RealtimeClientOptions(
          headers: ["apikey": "test-key"],
          accessToken: { "test-token" }
        ),
        wsTransport: { _, _ in client },
        http: HTTPClientMock(),
        clock: ContinuousClock()
      )

      let channel = socket.channel("test-topic")

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

      await socket.connect()
      try? await channel.subscribeWithError()
      #expect(channel.status == .subscribed)

      let callbackCountBefore = channel.callbackManager.callbacks.count

      _ = channel.onPostgresChange(AnyAction.self, schema: "public") { _ in }

      #expect(channel.callbackManager.callbacks.count == callbackCountBefore)

      socket.disconnect()
    }
  #endif

  @Test
  func attachCallbacks() {
    var subscriptions = Set<RealtimeSubscription>()

    sut.onPostgresChange(
      AnyAction.self,
      schema: "public",
      table: "users",
      filter: "id=eq.1"
    ) { _ in }.store(in: &subscriptions)
    sut.onPostgresChange(
      InsertAction.self,
      schema: "private"
    ) { _ in }.store(in: &subscriptions)
    sut.onPostgresChange(
      UpdateAction.self,
      table: "messages"
    ) { _ in }.store(in: &subscriptions)
    sut.onPostgresChange(
      DeleteAction.self
    ) { _ in }.store(in: &subscriptions)

    sut.onBroadcast(event: "test") { _ in }.store(in: &subscriptions)
    sut.onBroadcast(event: "cursor-pos") { _ in }.store(in: &subscriptions)

    sut.onPresenceChange { _ in }.store(in: &subscriptions)

    sut.onSystem {
    }
    .store(in: &subscriptions)

    assertInlineSnapshot(of: sut.callbackManager.callbacks, as: .dump) {
      """
      ▿ 8 elements
        ▿ RealtimeCallback
          ▿ postgres: PostgresCallback
            - callback: (Function)
            ▿ filter: PostgresJoinConfig
              ▿ event: Optional<PostgresChangeEvent>
                - some: PostgresChangeEvent.all
              ▿ filter: Optional<String>
                - some: "id=eq.1"
              - id: 0
              - schema: "public"
              - select: Optional<Array<String>>.none
              ▿ table: Optional<String>
                - some: "users"
            - id: 1
        ▿ RealtimeCallback
          ▿ postgres: PostgresCallback
            - callback: (Function)
            ▿ filter: PostgresJoinConfig
              ▿ event: Optional<PostgresChangeEvent>
                - some: PostgresChangeEvent.insert
              - filter: Optional<String>.none
              - id: 0
              - schema: "private"
              - select: Optional<Array<String>>.none
              - table: Optional<String>.none
            - id: 2
        ▿ RealtimeCallback
          ▿ postgres: PostgresCallback
            - callback: (Function)
            ▿ filter: PostgresJoinConfig
              ▿ event: Optional<PostgresChangeEvent>
                - some: PostgresChangeEvent.update
              - filter: Optional<String>.none
              - id: 0
              - schema: "public"
              - select: Optional<Array<String>>.none
              ▿ table: Optional<String>
                - some: "messages"
            - id: 3
        ▿ RealtimeCallback
          ▿ postgres: PostgresCallback
            - callback: (Function)
            ▿ filter: PostgresJoinConfig
              ▿ event: Optional<PostgresChangeEvent>
                - some: PostgresChangeEvent.delete
              - filter: Optional<String>.none
              - id: 0
              - schema: "public"
              - select: Optional<Array<String>>.none
              - table: Optional<String>.none
            - id: 4
        ▿ RealtimeCallback
          ▿ broadcast: BroadcastCallback
            - callback: (Function)
            - event: "test"
            - id: 5
        ▿ RealtimeCallback
          ▿ broadcast: BroadcastCallback
            - callback: (Function)
            - event: "cursor-pos"
            - id: 6
        ▿ RealtimeCallback
          ▿ presence: PresenceCallback
            - callback: (Function)
            - id: 7
        ▿ RealtimeCallback
          ▿ system: SystemCallback
            - callback: (Function)
            - id: 8

      """
    }
  }

  @Test
  @MainActor
  func presenceEnabledDuringSubscribe() async {
    // Create fake WebSocket for testing
    let (client, server) = FakeWebSocket.fakes()

    let socket = RealtimeClientV2(
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClientMock(),
      clock: ContinuousClock()
    )

    // Create a channel without presence callback initially
    let channel = socket.channel("test-topic")

    // Initially presence should be disabled
    #expect(!channel.config.presence.enabled)

    // Connect the socket
    await socket.connect()

    // Add a presence callback before subscribing
    let presenceSubscription = channel.onPresenceChange { _ in }

    // Verify that presence callback exists
    #expect(channel.callbackManager.callbacks.contains(where: { $0.isPresence }))

    // Start subscription process
    Task {
      try? await channel.subscribeWithError()
    }

    // Wait for the join message to be sent
    let joinEvents = await waitForEvents(
      in: server,
      event: "phx_join",
      timeout: 1.0
    )

    // Should have at least one join event
    #expect(joinEvents.count > 0)

    // Check that the presence enabled flag is set to true in the join payload
    if let joinEvent = joinEvents.first,
      let config = joinEvent.payload["config"]?.objectValue,
      let presence = config["presence"]?.objectValue,
      let enabled = presence["enabled"]?.boolValue
    {
      #expect(enabled, "Presence should be enabled when presence callback exists")
    } else {
      Issue.record("Could not find presence enabled flag in join payload")
    }

    // Clean up
    presenceSubscription.cancel()
    await channel.unsubscribe()
    socket.disconnect()

    // Note: We don't assert the subscribe status here because the test doesn't wait for completion
    // The subscription is still in progress when we clean up
  }

  @Test
  func httpSendThrowsWhenAccessTokenIsMissing() async {
    let httpClient = HTTPClientMock()
    let (client, _) = FakeWebSocket.fakes()

    let socket = RealtimeClientV2(
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(headers: ["apikey": "test-key"]),
      wsTransport: { _, _ in client },
      http: httpClient,
      clock: ContinuousClock()
    )

    let channel = socket.channel("test-topic")

    do {
      try await channel.httpSend(event: "test", message: ["data": "test"])
      Issue.record("Expected httpSend to throw an error when access token is missing")
    } catch {
      #expect(error.localizedDescription == "Access token is required for httpSend()")
    }
  }

  @Test
  func httpSendSucceedsOn202Status() async throws {
    let httpClient = HTTPClientMock()
    await httpClient.when({ _ in true }) { _ in
      HTTPResponse(
        data: Data(),
        response: HTTPURLResponse(
          url: URL(string: "https://localhost:54321/api/broadcast")!,
          statusCode: 202,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    }
    let (client, _) = FakeWebSocket.fakes()

    let socket = RealtimeClientV2(
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: httpClient,
      clock: ContinuousClock()
    )

    let channel = socket.channel("test-topic") { config in
      config.isPrivate = true
    }

    try await channel.httpSend(event: "test-event", message: ["data": "explicit"])

    let requests = await httpClient.receivedRequests
    #expect(requests.count == 1)

    let request = requests[0]
    #expect(
      request.url.absoluteString
        == "https://localhost:54321/realtime/v1/api/broadcast/test-topic/events/test-event?private=true"
    )
    #expect(request.method == .post)
    #expect(request.headers[.authorization] == "Bearer test-token")
    #expect(request.headers[.apiKey] == "test-key")
    #expect(request.headers[.contentType] == "application/json")

    let body = try JSONDecoder().decode([String: String].self, from: request.body ?? Data())
    #expect(body == ["data": "explicit"])
  }

  @Test
  func httpSendPercentEncodesTopicAndEventInURL() async throws {
    let httpClient = HTTPClientMock()
    await httpClient.when({ _ in true }) { _ in
      HTTPResponse(
        data: Data(),
        response: HTTPURLResponse(
          url: URL(string: "https://localhost:54321/api/broadcast")!,
          statusCode: 202,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    }
    let (client, _) = FakeWebSocket.fakes()

    let socket = RealtimeClientV2(
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: httpClient,
      clock: ContinuousClock()
    )

    let channel = socket.channel("room/one")

    try await channel.httpSend(event: "cursor move", message: ["x": 1])

    let requests = await httpClient.receivedRequests
    #expect(
      requests[0].url.absoluteString
        == "https://localhost:54321/realtime/v1/api/broadcast/room%2Fone/events/cursor%20move"
    )
  }

  @Test
  func httpSendWithBinaryDataSendsOctetStream() async throws {
    let httpClient = HTTPClientMock()
    await httpClient.when({ _ in true }) { _ in
      HTTPResponse(
        data: Data(),
        response: HTTPURLResponse(
          url: URL(string: "https://localhost:54321/api/broadcast")!,
          statusCode: 202,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    }
    let (client, _) = FakeWebSocket.fakes()

    let socket = RealtimeClientV2(
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: httpClient,
      clock: ContinuousClock()
    )

    let channel = socket.channel("test-topic")

    let payload = Data([0x01, 0x02, 0x03])
    try await channel.httpSend(event: "binary-event", data: payload)

    let requests = await httpClient.receivedRequests
    #expect(requests.count == 1)

    let request = requests[0]
    #expect(
      request.url.absoluteString
        == "https://localhost:54321/realtime/v1/api/broadcast/test-topic/events/binary-event"
    )
    #expect(request.headers[.contentType] == "application/octet-stream")
    #expect(request.body == payload)
  }

  @Test
  func httpSendWithBinaryDataThrowsWhenAccessTokenIsMissing() async {
    let httpClient = HTTPClientMock()
    let (client, _) = FakeWebSocket.fakes()

    let socket = RealtimeClientV2(
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(headers: ["apikey": "test-key"]),
      wsTransport: { _, _ in client },
      http: httpClient,
      clock: ContinuousClock()
    )

    let channel = socket.channel("test-topic")

    do {
      try await channel.httpSend(event: "test", data: Data([0x01]))
      Issue.record("Expected httpSend to throw an error when access token is missing")
    } catch {
      #expect(error.localizedDescription == "Access token is required for httpSend()")
    }
  }

  @Test
  func httpSendThrowsOnNon202Status() async {
    let httpClient = HTTPClientMock()
    await httpClient.when({ _ in true }) { _ in
      let errorBody = try JSONEncoder().encode(["error": "Server error"])
      return HTTPResponse(
        data: errorBody,
        response: HTTPURLResponse(
          url: URL(string: "https://localhost:54321/api/broadcast")!,
          statusCode: 500,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    }
    let (client, _) = FakeWebSocket.fakes()

    let socket = RealtimeClientV2(
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: httpClient,
      clock: ContinuousClock()
    )

    let channel = socket.channel("test-topic")

    do {
      try await channel.httpSend(event: "test", message: ["data": "test"])
      Issue.record("Expected httpSend to throw an error on non-202 status")
    } catch {
      #expect(error.localizedDescription == "Server error")
    }
  }

  @Test
  func httpSendRespectsCustomTimeout() async throws {
    let httpClient = HTTPClientMock()
    await httpClient.when({ _ in true }) { _ in
      HTTPResponse(
        data: Data(),
        response: HTTPURLResponse(
          url: URL(string: "https://localhost:54321/api/broadcast")!,
          statusCode: 202,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    }
    let (client, _) = FakeWebSocket.fakes()

    let socket = RealtimeClientV2(
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"],
        timeoutInterval: 5.0,
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: httpClient,
      clock: ContinuousClock()
    )

    let channel = socket.channel("test-topic")

    // Test with custom timeout
    try await channel.httpSend(event: "test", message: ["data": "test"], timeout: 3.0)

    let requests = await httpClient.receivedRequests
    #expect(requests.count == 1)
  }

  @Test
  func httpSendUsesDefaultTimeoutWhenNotSpecified() async throws {
    let httpClient = HTTPClientMock()
    await httpClient.when({ _ in true }) { _ in
      HTTPResponse(
        data: Data(),
        response: HTTPURLResponse(
          url: URL(string: "https://localhost:54321/api/broadcast")!,
          statusCode: 202,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    }
    let (client, _) = FakeWebSocket.fakes()

    let socket = RealtimeClientV2(
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"],
        timeoutInterval: 5.0,
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: httpClient,
      clock: ContinuousClock()
    )

    let channel = socket.channel("test-topic")

    // Test without custom timeout
    try await channel.httpSend(event: "test", message: ["data": "test"])

    let requests = await httpClient.receivedRequests
    #expect(requests.count == 1)
  }

  @Test
  func httpSendFallsBackToStatusTextWhenErrorBodyHasNoErrorField() async {
    let httpClient = HTTPClientMock()
    await httpClient.when({ _ in true }) { _ in
      let errorBody = try JSONEncoder().encode(["message": "Invalid request"])
      return HTTPResponse(
        data: errorBody,
        response: HTTPURLResponse(
          url: URL(string: "https://localhost:54321/api/broadcast")!,
          statusCode: 400,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    }
    let (client, _) = FakeWebSocket.fakes()

    let socket = RealtimeClientV2(
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: httpClient,
      clock: ContinuousClock()
    )

    let channel = socket.channel("test-topic")

    do {
      try await channel.httpSend(event: "test", message: ["data": "test"])
      Issue.record("Expected httpSend to throw an error on 400 status")
    } catch {
      #expect(error.localizedDescription == "Invalid request")
    }
  }

  @Test
  func httpSendFallsBackToStatusTextWhenJSONParsingFails() async {
    let httpClient = HTTPClientMock()
    await httpClient.when({ _ in true }) { _ in
      HTTPResponse(
        data: Data("Invalid JSON".utf8),
        response: HTTPURLResponse(
          url: URL(string: "https://localhost:54321/api/broadcast")!,
          statusCode: 503,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    }
    let (client, _) = FakeWebSocket.fakes()

    let socket = RealtimeClientV2(
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: httpClient,
      clock: ContinuousClock()
    )

    let channel = socket.channel("test-topic")

    do {
      try await channel.httpSend(event: "test", message: ["data": "test"])
      Issue.record("Expected httpSend to throw an error on 503 status")
    } catch {
      // Should fall back to localized status text (case-insensitive)
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
    func channelErrorResetsSubscribedStatus() async {
      let (client, server) = FakeWebSocket.fakes()
      let socket = RealtimeClientV2(
        url: URL(string: "https://localhost:54321/realtime/v1")!,
        options: RealtimeClientOptions(
          headers: ["apikey": "test-key"],
          accessToken: { "test-token" }
        ),
        wsTransport: { _, _ in client },
        http: HTTPClientMock(),
        clock: ContinuousClock()
      )

      let channel = socket.channel("test-topic")

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

      await socket.connect()
      try? await channel.subscribeWithError()
      #expect(channel.status == .subscribed)

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
      #expect(channel.status == .unsubscribed)

      socket.disconnect()
    }
  #endif
}

extension RealtimeChannelTests {
  @MainActor
  private func waitForChannelStatus(
    _ status: RealtimeChannelStatus,
    channel: RealtimeChannelV2,
    timeout: TimeInterval,
    pollInterval: UInt64 = 10_000_000
  ) async {
    await Testing_waitUntil(timeout: timeout, pollInterval: pollInterval) {
      channel.status == status
    }
  }

  @MainActor
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

/// `@MainActor`-safe wrapper around the shared, non-isolated `waitUntil` helper —
/// avoids a "passing a `@MainActor`-isolated closure as a `@Sendable` closure" diagnostic
/// when the condition captures main-actor-isolated state (e.g. `RealtimeChannelV2.status`).
@MainActor
private func Testing_waitUntil(
  timeout: TimeInterval,
  pollInterval: UInt64,
  condition: @MainActor @escaping () -> Bool
) async {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if condition() { return }
    try? await Task.sleep(nanoseconds: pollInterval)
  }
  _ = condition()
}
