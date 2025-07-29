//
//  TypesTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 29/07/25.
//

import XCTest
import HTTPTypes

@testable import Realtime

final class TypesTests: XCTestCase {
  func testRealtimeClientOptionsDefaults() {
    let options = RealtimeClientOptions()
    
    XCTAssertEqual(options.heartbeatInterval, RealtimeClientOptions.defaultHeartbeatInterval)
    XCTAssertEqual(options.reconnectDelay, RealtimeClientOptions.defaultReconnectDelay)
    XCTAssertEqual(options.timeoutInterval, RealtimeClientOptions.defaultTimeoutInterval)
    XCTAssertEqual(options.disconnectOnSessionLoss, RealtimeClientOptions.defaultDisconnectOnSessionLoss)
    XCTAssertEqual(options.connectOnSubscribe, RealtimeClientOptions.defaultConnectOnSubscribe)
    XCTAssertNil(options.logLevel)
    XCTAssertNil(options.fetch)
    XCTAssertNil(options.accessToken)
    XCTAssertNil(options.logger)
    XCTAssertNil(options.apikey)
  }
  
  func testRealtimeClientOptionsWithCustomValues() {
    let customHeaders = ["Authorization": "Bearer token", "Custom-Header": "value"]
    let options = RealtimeClientOptions(
      headers: customHeaders,
      heartbeatInterval: 30,
      reconnectDelay: 5,
      timeoutInterval: 15,
      disconnectOnSessionLoss: false,
      connectOnSubscribe: false,
      logLevel: .info
    )
    
    XCTAssertEqual(options.heartbeatInterval, 30)
    XCTAssertEqual(options.reconnectDelay, 5)
    XCTAssertEqual(options.timeoutInterval, 15)
    XCTAssertEqual(options.disconnectOnSessionLoss, false)
    XCTAssertEqual(options.connectOnSubscribe, false)
    XCTAssertEqual(options.logLevel, .info)
    
    // Test HTTPFields conversion
    XCTAssertEqual(options.headers[HTTPField.Name("Authorization")!], "Bearer token")
    XCTAssertEqual(options.headers[HTTPField.Name("Custom-Header")!], "value")
  }
  
  func testRealtimeClientOptionsWithApiKey() {
    let options = RealtimeClientOptions(
      headers: ["apiKey": "test-api-key"]
    )
    
    XCTAssertEqual(options.apikey, "test-api-key")
  }
  
  func testRealtimeClientOptionsWithoutApiKey() {
    let options = RealtimeClientOptions(
      headers: ["Authorization": "Bearer token"]
    )
    
    XCTAssertNil(options.apikey)
  }
  
  func testRealtimeClientOptionsWithAccessToken() {
    let accessTokenProvider: @Sendable () async throws -> String? = {
      return "access-token"
    }
    
    let options = RealtimeClientOptions(
      accessToken: accessTokenProvider
    )
    
    XCTAssertNotNil(options.accessToken)
  }
  
  func testRealtimeChannelStatusValues() {
    XCTAssertEqual(RealtimeChannelStatus.unsubscribed, .unsubscribed)
    XCTAssertEqual(RealtimeChannelStatus.subscribing, .subscribing)
    XCTAssertEqual(RealtimeChannelStatus.subscribed, .subscribed)
    XCTAssertEqual(RealtimeChannelStatus.unsubscribing, .unsubscribing)
  }
  
  func testRealtimeClientStatusValues() {
    XCTAssertEqual(RealtimeClientStatus.disconnected, .disconnected)
    XCTAssertEqual(RealtimeClientStatus.connecting, .connecting)
    XCTAssertEqual(RealtimeClientStatus.connected, .connected)
  }
  
  func testRealtimeClientStatusDescription() {
    XCTAssertEqual(RealtimeClientStatus.disconnected.description, "Disconnected")
    XCTAssertEqual(RealtimeClientStatus.connecting.description, "Connecting")
    XCTAssertEqual(RealtimeClientStatus.connected.description, "Connected")
  }
  
  func testHeartbeatStatusValues() {
    XCTAssertEqual(HeartbeatStatus.sent, .sent)
    XCTAssertEqual(HeartbeatStatus.ok, .ok)
    XCTAssertEqual(HeartbeatStatus.error, .error)
    XCTAssertEqual(HeartbeatStatus.timeout, .timeout)
    XCTAssertEqual(HeartbeatStatus.disconnected, .disconnected)
  }
  
  func testLogLevelValues() {
    XCTAssertEqual(LogLevel.info.rawValue, "info")
    XCTAssertEqual(LogLevel.warn.rawValue, "warn")
    XCTAssertEqual(LogLevel.error.rawValue, "error")
  }
  
  func testLogLevelInitFromRawValue() {
    XCTAssertEqual(LogLevel(rawValue: "info"), .info)
    XCTAssertEqual(LogLevel(rawValue: "warn"), .warn)
    XCTAssertEqual(LogLevel(rawValue: "error"), .error)
    XCTAssertNil(LogLevel(rawValue: "invalid"))
  }
  
  func testHTTPFieldNameApiKey() {
    let apiKeyField = HTTPField.Name.apiKey
    XCTAssertEqual(apiKeyField.rawName, "apiKey")
  }
  
  func testRealtimeSubscriptionTypeAlias() {
    // Test that RealtimeSubscription is correctly aliased to ObservationToken
    let token = ObservationToken {
      // Empty cleanup
    }
    let subscription: RealtimeSubscription = token
    XCTAssertNotNil(subscription)
  }
  
  func testDefaultValues() {
    XCTAssertEqual(RealtimeClientOptions.defaultHeartbeatInterval, 25)
    XCTAssertEqual(RealtimeClientOptions.defaultReconnectDelay, 7)
    XCTAssertEqual(RealtimeClientOptions.defaultTimeoutInterval, 10)
    XCTAssertEqual(RealtimeClientOptions.defaultDisconnectOnSessionLoss, true)
    XCTAssertEqual(RealtimeClientOptions.defaultConnectOnSubscribe, true)
  }
}