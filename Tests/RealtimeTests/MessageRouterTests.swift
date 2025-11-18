//
//  MessageRouterTests.swift
//  Realtime Tests
//
//  Created on 17/01/25.
//

import ConcurrencyExtras
import Foundation
import XCTest

@testable import Realtime

final class MessageRouterTests: XCTestCase {
  var router: MessageRouter!
  var receivedMessages: [RealtimeMessageV2] = []

  override func setUp() async throws {
    try await super.setUp()
    router = MessageRouter(logger: nil)
    receivedMessages = []
  }

  override func tearDown() async throws {
    router = nil
    receivedMessages = []
    try await super.tearDown()
  }

  // MARK: - Helper

  func makeMessage(topic: String, event: String) -> RealtimeMessageV2 {
    RealtimeMessageV2(
      joinRef: nil,
      ref: nil,
      topic: topic,
      event: event,
      payload: [:]
    )
  }

  // MARK: - Tests

  func testRouteToRegisteredChannel() async {
    let channelAMessages = LockIsolated([RealtimeMessageV2]())
    let channelBMessages = LockIsolated([RealtimeMessageV2]())

    await router.registerChannel(topic: "channel-a") { message in
      channelAMessages.withValue { $0.append(message) }
    }

    await router.registerChannel(topic: "channel-b") { message in
      channelBMessages.withValue { $0.append(message) }
    }

    let messageA = makeMessage(topic: "channel-a", event: "test")
    let messageB = makeMessage(topic: "channel-b", event: "test")

    await router.route(messageA)
    await router.route(messageB)

    XCTAssertEqual(channelAMessages.value.count, 1)
    XCTAssertEqual(channelAMessages.value.first?.topic, "channel-a")

    XCTAssertEqual(channelBMessages.value.count, 1)
    XCTAssertEqual(channelBMessages.value.first?.topic, "channel-b")
  }

  func testRouteToUnregisteredChannelDoesNotCrash() async {
    let message = makeMessage(topic: "unknown-channel", event: "test")

    // Should not crash
    await router.route(message)
  }

  func testSystemHandlerReceivesAllMessages() async {
    let systemMessages = LockIsolated([RealtimeMessageV2]())

    await router.registerSystemHandler { message in
      systemMessages.withValue { $0.append(message) }
    }

    let message1 = makeMessage(topic: "channel-a", event: "event1")
    let message2 = makeMessage(topic: "channel-b", event: "event2")
    let message3 = makeMessage(topic: "channel-c", event: "event3")

    await router.route(message1)
    await router.route(message2)
    await router.route(message3)

    XCTAssertEqual(systemMessages.value.count, 3)
    XCTAssertEqual(systemMessages.value[0].topic, "channel-a")
    XCTAssertEqual(systemMessages.value[1].topic, "channel-b")
    XCTAssertEqual(systemMessages.value[2].topic, "channel-c")
  }

  func testBothSystemAndChannelHandlersReceiveMessage() async {
    let systemMessages = LockIsolated([RealtimeMessageV2]())
    let channelMessages = LockIsolated([RealtimeMessageV2]())

    await router.registerSystemHandler { message in
      systemMessages.withValue { $0.append(message) }
    }

    await router.registerChannel(topic: "test-channel") { message in
      channelMessages.withValue { $0.append(message) }
    }

    let message = makeMessage(topic: "test-channel", event: "test")
    await router.route(message)

    XCTAssertEqual(systemMessages.value.count, 1)
    XCTAssertEqual(channelMessages.value.count, 1)
  }

  func testUnregisterChannelStopsRoutingToIt() async {
    let channelMessages = LockIsolated([RealtimeMessageV2]())

    await router.registerChannel(topic: "test-channel") { message in
      channelMessages.withValue { $0.append(message) }
    }

    let message1 = makeMessage(topic: "test-channel", event: "test1")
    await router.route(message1)

    XCTAssertEqual(channelMessages.value.count, 1)

    // Unregister
    await router.unregisterChannel(topic: "test-channel")

    let message2 = makeMessage(topic: "test-channel", event: "test2")
    await router.route(message2)

    // Should still be 1 (not routed after unregister)
    XCTAssertEqual(channelMessages.value.count, 1)
  }

  func testReregisterChannelReplacesHandler() async {
    let handler1Messages = LockIsolated([RealtimeMessageV2]())
    let handler2Messages = LockIsolated([RealtimeMessageV2]())

    await router.registerChannel(topic: "test-channel") { message in
      handler1Messages.withValue { $0.append(message) }
    }

    let message1 = makeMessage(topic: "test-channel", event: "test1")
    await router.route(message1)

    XCTAssertEqual(handler1Messages.value.count, 1)
    XCTAssertEqual(handler2Messages.value.count, 0)

    // Re-register with new handler
    await router.registerChannel(topic: "test-channel") { message in
      handler2Messages.withValue { $0.append(message) }
    }

    let message2 = makeMessage(topic: "test-channel", event: "test2")
    await router.route(message2)

    // First handler should not receive second message
    XCTAssertEqual(handler1Messages.value.count, 1)
    // Second handler should receive it
    XCTAssertEqual(handler2Messages.value.count, 1)
  }

  func testResetRemovesAllHandlers() async {
    let channelMessages = LockIsolated([RealtimeMessageV2]())
    let systemMessages = LockIsolated([RealtimeMessageV2]())

    await router.registerChannel(topic: "channel-a") { message in
      channelMessages.withValue { $0.append(message) }
    }

    await router.registerSystemHandler { message in
      systemMessages.withValue { $0.append(message) }
    }

    let message1 = makeMessage(topic: "channel-a", event: "test1")
    await router.route(message1)

    XCTAssertEqual(channelMessages.count, 1)
    XCTAssertEqual(systemMessages.count, 1)

    // Reset
    await router.reset()

    let message2 = makeMessage(topic: "channel-a", event: "test2")
    await router.route(message2)

    // No more messages after reset
    XCTAssertEqual(channelMessages.value.count, 1)
    XCTAssertEqual(systemMessages.value.count, 1)
  }

  func testChannelCountReflectsRegistrations() async {
    var count = await router.channelCount
    XCTAssertEqual(count, 0)

    await router.registerChannel(topic: "channel-a") { _ in }
    count = await router.channelCount
    XCTAssertEqual(count, 1)

    await router.registerChannel(topic: "channel-b") { _ in }
    count = await router.channelCount
    XCTAssertEqual(count, 2)

    await router.unregisterChannel(topic: "channel-a")
    count = await router.channelCount
    XCTAssertEqual(count, 1)

    await router.reset()
    count = await router.channelCount
    XCTAssertEqual(count, 0)
  }

  func testMultipleSystemHandlers() async {
    let system1Messages = LockIsolated([RealtimeMessageV2]())
    let system2Messages = LockIsolated([RealtimeMessageV2]())

    await router.registerSystemHandler { message in
      system1Messages.withValue { $0.append(message) }
    }

    await router.registerSystemHandler { message in
      system2Messages.withValue { $0.append(message) }
    }

    let message = makeMessage(topic: "test", event: "test")
    await router.route(message)

    XCTAssertEqual(system1Messages.value.count, 1)
    XCTAssertEqual(system2Messages.value.count, 1)
  }

  func testConcurrentRouting() async {
    let receivedCount = LockIsolated(0)

    await router.registerChannel(topic: "test-channel") { _ in
      receivedCount.withValue { $0 += 1 }
    }

    // Route messages concurrently
    await withTaskGroup(of: Void.self) { group in
      for i in 0..<100 {
        group.addTask {
          let message = self.makeMessage(topic: "test-channel", event: "test-\(i)")
          await self.router.route(message)
        }
      }

      await group.waitForAll()
    }

    XCTAssertEqual(receivedCount.value, 100, "Should receive all messages")
  }
}
