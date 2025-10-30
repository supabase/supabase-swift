//
//  RealtimeChannelTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 09/09/24.
//

import InlineSnapshotTesting
import TestHelpers
import XCTest
import XCTestDynamicOverlay

@testable import Realtime

@MainActor
final class RealtimeChannelTests: XCTestCase {
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

  func testAttachCallbacks() {
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

  @MainActor
  func testPresenceEnabledDuringSubscribe() async {
    // Create fake WebSocket for testing
    let (client, server) = FakeWebSocket.fakes()

    let socket = RealtimeClientV2(
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClientMock()
    )

    // Create a channel without presence callback initially
    let channel = socket.channel("test-topic")

    // Initially presence should be disabled
    XCTAssertFalse(channel.config.presence.enabled)

    // Connect the socket
    await socket.connect()

    // Add a presence callback before subscribing
    let presenceSubscription = channel.onPresenceChange { _ in }

    // Verify that presence callback exists
    XCTAssertTrue(channel.callbackManager.callbacks.contains(where: { $0.isPresence }))

    // Start subscription process
    Task {
      try? await channel.subscribeWithError()
    }

    // Wait for the join message to be sent
    await Task.megaYield()

    // Check the sent events to verify presence enabled is set correctly
    let joinEvents = server.receivedEvents.compactMap { $0.realtimeMessage }.filter {
      $0.event == "phx_join"
    }

    // Should have at least one join event
    XCTAssertGreaterThan(joinEvents.count, 0)

    // Check that the presence enabled flag is set to true in the join payload
    if let joinEvent = joinEvents.first,
      let config = joinEvent.payload["config"]?.objectValue,
      let presence = config["presence"]?.objectValue,
      let enabled = presence["enabled"]?.boolValue
    {
      XCTAssertTrue(enabled, "Presence should be enabled when presence callback exists")
    } else {
      XCTFail("Could not find presence enabled flag in join payload")
    }

    // Clean up
    presenceSubscription.cancel()
    await channel.unsubscribe()
    socket.disconnect()

    // Note: We don't assert the subscribe status here because the test doesn't wait for completion
    // The subscription is still in progress when we clean up
  }

  func testHttpSendThrowsWhenAccessTokenIsMissing() async {
    let httpClient = HTTPClientMock()
    let (client, _) = FakeWebSocket.fakes()

    let socket = RealtimeClientV2(
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(headers: ["apikey": "test-key"]),
      wsTransport: { _, _ in client },
      http: httpClient
    )

    let channel = socket.channel("test-topic")

    do {
      try await channel.httpSend(event: "test", message: ["data": "test"])
      XCTFail("Expected httpSend to throw an error when access token is missing")
    } catch {
      XCTAssertEqual(error.localizedDescription, "Access token is required for httpSend()")
    }
  }

  func testHttpSendSucceedsOn202Status() async throws {
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
      http: httpClient
    )

    let channel = socket.channel("test-topic") { config in
      config.isPrivate = true
    }

    try await channel.httpSend(event: "test-event", message: ["data": "explicit"])

    let requests = await httpClient.receivedRequests
    XCTAssertEqual(requests.count, 1)

    let request = requests[0]
    XCTAssertEqual(request.url.absoluteString, "https://localhost:54321/realtime/v1/api/broadcast")
    XCTAssertEqual(request.method, .post)
    XCTAssertEqual(request.headers[.authorization], "Bearer test-token")
    XCTAssertEqual(request.headers[.apiKey], "test-key")
    XCTAssertEqual(request.headers[.contentType], "application/json")

    let body = try JSONDecoder().decode(BroadcastPayload.self, from: request.body ?? Data())
    XCTAssertEqual(body.messages.count, 1)
    XCTAssertEqual(body.messages[0].topic, "realtime:test-topic")
    XCTAssertEqual(body.messages[0].event, "test-event")
    XCTAssertEqual(body.messages[0].private, true)
  }

  func testHttpSendThrowsOnNon202Status() async {
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
      http: httpClient
    )

    let channel = socket.channel("test-topic")

    do {
      try await channel.httpSend(event: "test", message: ["data": "test"])
      XCTFail("Expected httpSend to throw an error on non-202 status")
    } catch {
      XCTAssertEqual(error.localizedDescription, "Server error")
    }
  }

  func testHttpSendRespectsCustomTimeout() async throws {
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
      http: httpClient
    )

    let channel = socket.channel("test-topic")

    // Test with custom timeout
    try await channel.httpSend(event: "test", message: ["data": "test"], timeout: 3.0)

    let requests = await httpClient.receivedRequests
    XCTAssertEqual(requests.count, 1)
  }

  func testHttpSendUsesDefaultTimeoutWhenNotSpecified() async throws {
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
      http: httpClient
    )

    let channel = socket.channel("test-topic")

    // Test without custom timeout
    try await channel.httpSend(event: "test", message: ["data": "test"])

    let requests = await httpClient.receivedRequests
    XCTAssertEqual(requests.count, 1)
  }

  func testHttpSendFallsBackToStatusTextWhenErrorBodyHasNoErrorField() async {
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
      http: httpClient
    )

    let channel = socket.channel("test-topic")

    do {
      try await channel.httpSend(event: "test", message: ["data": "test"])
      XCTFail("Expected httpSend to throw an error on 400 status")
    } catch {
      XCTAssertEqual(error.localizedDescription, "Invalid request")
    }
  }

  func testHttpSendFallsBackToStatusTextWhenJSONParsingFails() async {
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
      http: httpClient
    )

    let channel = socket.channel("test-topic")

    do {
      try await channel.httpSend(event: "test", message: ["data": "test"])
      XCTFail("Expected httpSend to throw an error on 503 status")
    } catch {
      // Should fall back to localized status text
      XCTAssertTrue(error.localizedDescription.contains("503") || error.localizedDescription.contains("unavailable"))
    }
  }
}

// Helper struct for decoding broadcast payload in tests
private struct BroadcastPayload: Decodable {
  let messages: [Message]

  struct Message: Decodable {
    let topic: String
    let event: String
    let payload: [String: String]
    let `private`: Bool
  }
}
