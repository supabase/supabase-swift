//
//  RealtimeChannelTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 09/09/24.
//

import InlineSnapshotTesting
import TestHelpers
import WebSocket
import XCTest
import XCTestDynamicOverlay

@testable import Realtime

@MainActor
final class RealtimeChannelTests: XCTestCase {
  var socket: RealtimeClientV2!
  var sut: RealtimeChannelV2!

  var serverWs: FakeWebSocket!

  override func setUp() {
    super.setUp()

    let (client, server) = FakeWebSocket.fakes()
    self.serverWs = server

    socket = RealtimeClientV2(
      url: URL(string: "http://localhost:3000")!,
      options: RealtimeClientOptions(),
      wsFactory: { _, _ in client },
      http: HTTPClientMock()
    )

    sut = RealtimeChannelV2(
      socket,
      topic: "topic",
      config: RealtimeChannelConfig(
        broadcast: BroadcastJoinConfig(),
        presence: PresenceJoinConfig(),
        isPrivate: false
      ),
      logger: nil
    )
  }

  func testAttachCallbacks() async {
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

    let callbacks = sut.callbackManager.callbacks
    assertInlineSnapshot(of: callbacks, as: .dump) {
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
}
