//
//  WebSocketTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 29/07/25.
//

import ConcurrencyExtras
import XCTest

@testable import Realtime

final class WebSocketTests: XCTestCase {

  // MARK: - WebSocketEvent Tests

  func testWebSocketEventEquality() {
    let textEvent1 = WebSocketEvent.text("hello")
    let textEvent2 = WebSocketEvent.text("hello")
    let textEvent3 = WebSocketEvent.text("world")

    XCTAssertEqual(textEvent1, textEvent2)
    XCTAssertNotEqual(textEvent1, textEvent3)

    let binaryData = Data([1, 2, 3])
    let binaryEvent1 = WebSocketEvent.binary(binaryData)
    let binaryEvent2 = WebSocketEvent.binary(binaryData)
    let binaryEvent3 = WebSocketEvent.binary(Data([4, 5, 6]))

    XCTAssertEqual(binaryEvent1, binaryEvent2)
    XCTAssertNotEqual(binaryEvent1, binaryEvent3)

    let closeEvent1 = WebSocketEvent.close(code: 1000, reason: "normal")
    let closeEvent2 = WebSocketEvent.close(code: 1000, reason: "normal")
    let closeEvent3 = WebSocketEvent.close(code: 1001, reason: "going away")

    XCTAssertEqual(closeEvent1, closeEvent2)
    XCTAssertNotEqual(closeEvent1, closeEvent3)
  }

  func testWebSocketEventHashable() {
    let textEvent = WebSocketEvent.text("hello")
    let binaryEvent = WebSocketEvent.binary(Data([1, 2, 3]))
    let closeEvent = WebSocketEvent.close(code: 1000, reason: "normal")

    let events: Set<WebSocketEvent> = [textEvent, binaryEvent, closeEvent]
    XCTAssertEqual(events.count, 3)
  }

  func testWebSocketEventPatternMatching() {
    let textEvent = WebSocketEvent.text("hello world")
    let binaryEvent = WebSocketEvent.binary(Data([1, 2, 3]))
    let closeEvent = WebSocketEvent.close(code: 1000, reason: "normal")

    switch textEvent {
    case .text(let message):
      XCTAssertEqual(message, "hello world")
    default:
      XCTFail("Expected text event")
    }

    switch binaryEvent {
    case .binary(let data):
      XCTAssertEqual(data, Data([1, 2, 3]))
    default:
      XCTFail("Expected binary event")
    }

    switch closeEvent {
    case .close(let code, let reason):
      XCTAssertEqual(code, 1000)
      XCTAssertEqual(reason, "normal")
    default:
      XCTFail("Expected close event")
    }
  }

  // MARK: - WebSocketError Tests

  func testWebSocketErrorConnection() {
    let underlyingError = NSError(
      domain: "TestDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error"])
    let webSocketError = WebSocketError.connection(
      message: "Connection failed", error: underlyingError)

    XCTAssertEqual(webSocketError.errorDescription, "Connection failed Test error")
  }

  func testWebSocketErrorAsError() {
    let underlyingError = NSError(
      domain: "TestDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error"])
    let webSocketError = WebSocketError.connection(
      message: "Connection failed", error: underlyingError)
    let error: Error = webSocketError

    XCTAssertEqual(error.localizedDescription, "Connection failed Test error")
  }
}
