//
//  RealtimeChannelTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 09/09/24.
//

import InlineSnapshotTesting
@testable import Realtime
import XCTest
import XCTestDynamicOverlay

final class RealtimeChannelTests: XCTestCase {
  var sut: RealtimeChannelV2!

  func testOnPostgresChange() {
    sut = RealtimeChannelV2(
      topic: "topic",
      config: RealtimeChannelConfig(
        broadcast: BroadcastJoinConfig(),
        presence: PresenceJoinConfig(),
        isPrivate: false
      ),
      socket: .mock,
      logger: nil
    )
    var subscriptions = Set<RealtimeChannelV2.Subscription>()
    sut.onPostgresChange(AnyAction.self) { _ in }.store(in: &subscriptions)
    sut.onPostgresChange(InsertAction.self) { _ in }.store(in: &subscriptions)
    sut.onPostgresChange(UpdateAction.self) { _ in }.store(in: &subscriptions)
    sut.onPostgresChange(DeleteAction.self) { _ in }.store(in: &subscriptions)

    assertInlineSnapshot(of: sut.callbackManager.callbacks, as: .dump) {
      """
      ▿ 4 elements
        ▿ RealtimeCallback
          ▿ postgres: PostgresCallback
            - callback: (Function)
            ▿ filter: PostgresJoinConfig
              ▿ event: Optional<PostgresChangeEvent>
                - some: PostgresChangeEvent.all
              - filter: Optional<String>.none
              - id: 0
              - schema: "public"
              - table: Optional<String>.none
            - id: 1
        ▿ RealtimeCallback
          ▿ postgres: PostgresCallback
            - callback: (Function)
            ▿ filter: PostgresJoinConfig
              ▿ event: Optional<PostgresChangeEvent>
                - some: PostgresChangeEvent.insert
              - filter: Optional<String>.none
              - id: 0
              - schema: "public"
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
              - table: Optional<String>.none
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

      """
    }
  }
}

extension Socket {
  static var mock: Socket {
    Socket(
      broadcastURL: unimplemented(),
      status: unimplemented(),
      options: unimplemented(),
      accessToken: unimplemented(),
      apiKey: unimplemented(),
      makeRef: unimplemented(),
      connect: unimplemented(),
      addChannel: unimplemented(),
      removeChannel: unimplemented(),
      push: unimplemented(),
      httpSend: unimplemented()
    )
  }
}
