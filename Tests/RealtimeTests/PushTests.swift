//
//  PushTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 29/07/25.
//

import ConcurrencyExtras
import XCTest

@testable import Realtime

final class PushTests: XCTestCase {

  func testPushStatusValues() {
    XCTAssertEqual(PushStatus.ok.rawValue, "ok")
    XCTAssertEqual(PushStatus.error.rawValue, "error")
    XCTAssertEqual(PushStatus.timeout.rawValue, "timeout")
  }

  func testPushStatusFromRawValue() {
    XCTAssertEqual(PushStatus(rawValue: "ok"), .ok)
    XCTAssertEqual(PushStatus(rawValue: "error"), .error)
    XCTAssertEqual(PushStatus(rawValue: "timeout"), .timeout)
    XCTAssertNil(PushStatus(rawValue: "invalid"))
  }

  @MainActor
  func testPushInitializationWithNilChannel() {
    let sampleMessage = RealtimeMessage(
      joinRef: "ref1",
      ref: "ref2",
      topic: "test:channel",
      event: "broadcast",
      payload: ["data": "test"]
    )

    let push = Push(channel: nil, message: sampleMessage)

    XCTAssertEqual(push.message.topic, "test:channel")
    XCTAssertEqual(push.message.event, "broadcast")
  }

  @MainActor
  func testSendWithNilChannelReturnsError() async {
    let sampleMessage = RealtimeMessage(
      joinRef: "ref1",
      ref: "ref2",
      topic: "test:channel",
      event: "broadcast",
      payload: ["data": "test"]
    )

    let push = Push(channel: nil, message: sampleMessage)

    let status = await push.send()

    XCTAssertEqual(status, .error)
  }

  @MainActor
  func testSendWithAckDisabledReturnsOkImmediately() async {
    let mockSocket = MockRealtimeClient()
    let config = RealtimeChannelConfig(
      broadcast: BroadcastJoinConfig(acknowledgeBroadcasts: false, receiveOwnBroadcasts: false),
      presence: PresenceJoinConfig(key: "", enabled: false),
      isPrivate: false
    )
    let mockChannel = MockRealtimeChannel(
      topic: "test:channel",
      config: config,
      socket: mockSocket,
      logger: nil
    )

    let sampleMessage = RealtimeMessage(
      joinRef: "ref1",
      ref: "ref2",
      topic: "test:channel",
      event: "broadcast",
      payload: ["data": "test"]
    )

    let push = Push(channel: mockChannel, message: sampleMessage)
    let status = await push.send()

    XCTAssertEqual(status, PushStatus.ok)
    XCTAssertEqual(mockSocket.pushedMessages.count, 1)
    XCTAssertEqual(mockSocket.pushedMessages.first?.topic, "test:channel")
    XCTAssertEqual(mockSocket.pushedMessages.first?.event, "broadcast")
  }

  @MainActor
  func testSendWithAckEnabledWaitsForResponse() async {
    let mockSocket = MockRealtimeClient()
    let config = RealtimeChannelConfig(
      broadcast: BroadcastJoinConfig(acknowledgeBroadcasts: true, receiveOwnBroadcasts: false),
      presence: PresenceJoinConfig(key: "", enabled: false),
      isPrivate: false
    )
    let mockChannel = MockRealtimeChannel(
      topic: "test:channel",
      config: config,
      socket: mockSocket,
      logger: nil
    )

    let sampleMessage = RealtimeMessage(
      joinRef: "ref1",
      ref: "ref2",
      topic: "test:channel",
      event: "broadcast",
      payload: ["data": "test"]
    )

    let push = Push(channel: mockChannel, message: sampleMessage)

    let sendTask = Task {
      await push.send()
    }

    // Give push time to start waiting
    try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms

    // Simulate receiving acknowledgment
    push.didReceive(status: PushStatus.ok)

    let status = await sendTask.value
    XCTAssertEqual(status, PushStatus.ok)
    XCTAssertEqual(mockSocket.pushedMessages.count, 1)
  }

  @MainActor
  func testChannelConfigurationForAcknowledgment() {
    // Test that the channel configuration is properly checked for acknowledgment settings
    let mockSocket = MockRealtimeClient()

    // Test acknowledgment disabled
    let configAckDisabled = RealtimeChannelConfig(
      broadcast: BroadcastJoinConfig(acknowledgeBroadcasts: false, receiveOwnBroadcasts: false),
      presence: PresenceJoinConfig(key: "", enabled: false),
      isPrivate: false
    )
    let channelAckDisabled = MockRealtimeChannel(
      topic: "test:channel",
      config: configAckDisabled,
      socket: mockSocket,
      logger: nil
    )
    XCTAssertFalse(channelAckDisabled.config.broadcast.acknowledgeBroadcasts)

    // Test acknowledgment enabled
    let configAckEnabled = RealtimeChannelConfig(
      broadcast: BroadcastJoinConfig(acknowledgeBroadcasts: true, receiveOwnBroadcasts: false),
      presence: PresenceJoinConfig(key: "", enabled: false),
      isPrivate: false
    )
    let channelAckEnabled = MockRealtimeChannel(
      topic: "test:channel",
      config: configAckEnabled,
      socket: mockSocket,
      logger: nil
    )
    XCTAssertTrue(channelAckEnabled.config.broadcast.acknowledgeBroadcasts)
  }

  @MainActor
  func testSendWithAckEnabledReceivesError() async {
    let mockSocket = MockRealtimeClient()
    let config = RealtimeChannelConfig(
      broadcast: BroadcastJoinConfig(acknowledgeBroadcasts: true, receiveOwnBroadcasts: false),
      presence: PresenceJoinConfig(key: "", enabled: false),
      isPrivate: false
    )
    let mockChannel = MockRealtimeChannel(
      topic: "test:channel",
      config: config,
      socket: mockSocket,
      logger: nil
    )

    let sampleMessage = RealtimeMessage(
      joinRef: "ref1",
      ref: "ref2",
      topic: "test:channel",
      event: "broadcast",
      payload: ["data": "test"]
    )

    let push = Push(channel: mockChannel, message: sampleMessage)

    let sendTask = Task {
      await push.send()
    }

    // Give push time to start waiting
    try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms

    // Simulate receiving error acknowledgment
    push.didReceive(status: PushStatus.error)

    let status = await sendTask.value
    XCTAssertEqual(status, PushStatus.error)
    XCTAssertEqual(mockSocket.pushedMessages.count, 1)
  }

  @MainActor
  func testDidReceiveStatusWithoutWaitingDoesNothing() {
    let sampleMessage = RealtimeMessage(
      joinRef: "ref1",
      ref: "ref2",
      topic: "test:channel",
      event: "broadcast",
      payload: ["data": "test"]
    )

    let push = Push(channel: nil, message: sampleMessage)

    // This should not crash or cause issues
    push.didReceive(status: PushStatus.ok)
    push.didReceive(status: PushStatus.error)
    push.didReceive(status: PushStatus.timeout)
  }

  @MainActor
  func testMultipleDidReceiveCallsOnlyFirstMatters() async {
    let mockSocket = MockRealtimeClient()
    let config = RealtimeChannelConfig(
      broadcast: BroadcastJoinConfig(acknowledgeBroadcasts: true, receiveOwnBroadcasts: false),
      presence: PresenceJoinConfig(key: "", enabled: false),
      isPrivate: false
    )
    let mockChannel = MockRealtimeChannel(
      topic: "test:channel",
      config: config,
      socket: mockSocket,
      logger: nil
    )

    let sampleMessage = RealtimeMessage(
      joinRef: "ref1",
      ref: "ref2",
      topic: "test:channel",
      event: "broadcast",
      payload: ["data": "test"]
    )

    let push = Push(channel: mockChannel, message: sampleMessage)

    let sendTask = Task {
      await push.send()
    }

    // Give push time to start waiting
    try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms

    // First response should be used
    push.didReceive(status: PushStatus.ok)

    // Subsequent responses should be ignored
    push.didReceive(status: PushStatus.error)
    push.didReceive(status: PushStatus.timeout)

    let status = await sendTask.value
    XCTAssertEqual(status, PushStatus.ok)  // Should be .ok, not .error or .timeout
  }
}

// MARK: - Mock Objects

@MainActor
private final class MockRealtimeChannel: RealtimeChannelProtocol {
  let topic: String
  var config: RealtimeChannelConfig
  let socket: any RealtimeClientProtocol
  let logger: SupabaseLogger?

  init(
    topic: String,
    config: RealtimeChannelConfig,
    socket: any RealtimeClientProtocol,
    logger: SupabaseLogger?
  ) {
    self.topic = topic
    self.config = config
    self.socket = socket
    self.logger = logger
  }
}

// TODO: Update for Alamofire - temporarily commented out
// These mocks need to be updated to work with Alamofire instead of HTTPClientType

import Alamofire

private final class MockRealtimeClient: RealtimeClientProtocol, @unchecked Sendable {
  private let _pushedMessages = LockIsolated<[RealtimeMessage]>([])
  private let _status = LockIsolated<RealtimeClientStatus>(.connected)
  let options: RealtimeClientOptions
  let session: Alamofire.Session = .default
  let broadcastURL = URL(string: "https://test.supabase.co/api/broadcast")!

  var status: RealtimeClientStatus {
    _status.value
  }

  init(timeoutInterval: TimeInterval = 10.0) {
    self.options = RealtimeClientOptions(
      timeoutInterval: timeoutInterval
    )
  }

  var pushedMessages: [RealtimeMessage] {
    _pushedMessages.value
  }

  func connect() async {
    _status.setValue(.connected)
  }

  func push(_ message: RealtimeMessage) {
    _pushedMessages.withValue { messages in
      messages.append(message)
    }
  }

  func _getAccessToken() async -> String? {
    return nil
  }

  func makeRef() -> String {
    return UUID().uuidString
  }

  func _remove(_ channel: any RealtimeChannelProtocol) {
    // No-op for mock
  }
}
