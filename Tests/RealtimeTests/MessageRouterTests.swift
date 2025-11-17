//
//  MessageRouterTests.swift
//  Realtime Tests
//
//  Created on 17/01/25.
//

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
    var channelAMessages: [RealtimeMessageV2] = []
    var channelBMessages: [RealtimeMessageV2] = []

    await router.registerChannel(topic: "channel-a") { message in
      channelAMessages.append(message)
    }

    await router.registerChannel(topic: "channel-b") { message in
      channelBMessages.append(message)
    }

    let messageA = makeMessage(topic: "channel-a", event: "test")
    let messageB = makeMessage(topic: "channel-b", event: "test")

    await router.route(messageA)
    await router.route(messageB)

    XCTAssertEqual(channelAMessages.count, 1)
    XCTAssertEqual(channelAMessages.first?.topic, "channel-a")

    XCTAssertEqual(channelBMessages.count, 1)
    XCTAssertEqual(channelBMessages.first?.topic, "channel-b")
  }

  func testRouteToUnregisteredChannelDoesNotCrash() async {
    let message = makeMessage(topic: "unknown-channel", event: "test")

    // Should not crash
    await router.route(message)
  }

  func testSystemHandlerReceivesAllMessages() async {
    var systemMessages: [RealtimeMessageV2] = []

    await router.registerSystemHandler { message in
      systemMessages.append(message)
    }

    let message1 = makeMessage(topic: "channel-a", event: "event1")
    let message2 = makeMessage(topic: "channel-b", event: "event2")
    let message3 = makeMessage(topic: "channel-c", event: "event3")

    await router.route(message1)
    await router.route(message2)
    await router.route(message3)

    XCTAssertEqual(systemMessages.count, 3)
    XCTAssertEqual(systemMessages[0].topic, "channel-a")
    XCTAssertEqual(systemMessages[1].topic, "channel-b")
    XCTAssertEqual(systemMessages[2].topic, "channel-c")
  }

  func testBothSystemAndChannelHandlersReceiveMessage() async {
    var systemMessages: [RealtimeMessageV2] = []
    var channelMessages: [RealtimeMessageV2] = []

    await router.registerSystemHandler { message in
      systemMessages.append(message)
    }

    await router.registerChannel(topic: "test-channel") { message in
      channelMessages.append(message)
    }

    let message = makeMessage(topic: "test-channel", event: "test")
    await router.route(message)

    XCTAssertEqual(systemMessages.count, 1)
    XCTAssertEqual(channelMessages.count, 1)
  }

  func testUnregisterChannelStopsRoutingToIt() async {
    var channelMessages: [RealtimeMessageV2] = []

    await router.registerChannel(topic: "test-channel") { message in
      channelMessages.append(message)
    }

    let message1 = makeMessage(topic: "test-channel", event: "test1")
    await router.route(message1)

    XCTAssertEqual(channelMessages.count, 1)

    // Unregister
    await router.unregisterChannel(topic: "test-channel")

    let message2 = makeMessage(topic: "test-channel", event: "test2")
    await router.route(message2)

    // Should still be 1 (not routed after unregister)
    XCTAssertEqual(channelMessages.count, 1)
  }

  func testReregisterChannelReplacesHandler() async {
    var handler1Messages: [RealtimeMessageV2] = []
    var handler2Messages: [RealtimeMessageV2] = []

    await router.registerChannel(topic: "test-channel") { message in
      handler1Messages.append(message)
    }

    let message1 = makeMessage(topic: "test-channel", event: "test1")
    await router.route(message1)

    XCTAssertEqual(handler1Messages.count, 1)
    XCTAssertEqual(handler2Messages.count, 0)

    // Re-register with new handler
    await router.registerChannel(topic: "test-channel") { message in
      handler2Messages.append(message)
    }

    let message2 = makeMessage(topic: "test-channel", event: "test2")
    await router.route(message2)

    // First handler should not receive second message
    XCTAssertEqual(handler1Messages.count, 1)
    // Second handler should receive it
    XCTAssertEqual(handler2Messages.count, 1)
  }

  func testResetRemovesAllHandlers() async {
    var channelMessages: [RealtimeMessageV2] = []
    var systemMessages: [RealtimeMessageV2] = []

    await router.registerChannel(topic: "channel-a") { message in
      channelMessages.append(message)
    }

    await router.registerSystemHandler { message in
      systemMessages.append(message)
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
    XCTAssertEqual(channelMessages.count, 1)
    XCTAssertEqual(systemMessages.count, 1)
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
    var system1Messages: [RealtimeMessageV2] = []
    var system2Messages: [RealtimeMessageV2] = []

    await router.registerSystemHandler { message in
      system1Messages.append(message)
    }

    await router.registerSystemHandler { message in
      system2Messages.append(message)
    }

    let message = makeMessage(topic: "test", event: "test")
    await router.route(message)

    XCTAssertEqual(system1Messages.count, 1)
    XCTAssertEqual(system2Messages.count, 1)
  }

  func testConcurrentRouting() async {
    var receivedCount = 0
    let lock = NSLock()

    await router.registerChannel(topic: "test-channel") { _ in
      lock.lock()
      receivedCount += 1
      lock.unlock()
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

    XCTAssertEqual(receivedCount, 100, "Should receive all messages")
  }
}
