//
//  RealtimeChannelTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 09/09/24.
//

import Alamofire
import InlineSnapshotTesting
import TestHelpers
import XCTest
import XCTestDynamicOverlay

@testable import Realtime

final class RealtimeChannelTests: XCTestCase {
 let sut = RealtimeChannel(
   topic: "topic",
   config: RealtimeChannelConfig(
     broadcast: BroadcastJoinConfig(),
     presence: PresenceJoinConfig(),
     isPrivate: false
   ),
   socket: RealtimeClient(
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

   let socket = RealtimeClient(
     url: URL(string: "https://localhost:54321/realtime/v1")!,
     options: RealtimeClientOptions(
       headers: ["apikey": "test-key"],
       accessToken: { "test-token" }
     ),
     wsTransport: { _, _ in client },
     session: .default
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
}
