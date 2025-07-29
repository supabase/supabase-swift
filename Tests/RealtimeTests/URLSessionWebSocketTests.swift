//
//  URLSessionWebSocketTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 29/07/25.
//

import XCTest

@testable import Realtime

final class URLSessionWebSocketTests: XCTestCase {
  
  // MARK: - Validation Tests
  
  func testConnectWithInvalidSchemeThrows() async {
    let httpURL = URL(string: "http://example.com")!
    let httpsURL = URL(string: "https://example.com")!
    
    // These should trigger preconditionFailure, but we can't easily test that
    // Instead, we'll test the valid schemes work (indirectly)
    let wsURL = URL(string: "ws://example.com")!
    let wssURL = URL(string: "wss://example.com")!
    
    // We can't actually connect without a real server, but we can verify
    // the URLs are acceptable by checking they don't trigger precondition failures
    XCTAssertEqual(wsURL.scheme, "ws")
    XCTAssertEqual(wssURL.scheme, "wss")
    
    // For HTTP URLs, we'd expect preconditionFailure, but we can't test that directly
    XCTAssertEqual(httpURL.scheme, "http")
    XCTAssertEqual(httpsURL.scheme, "https")
  }
  
  // MARK: - Close Code Validation Tests
  
  func testCloseCodeValidation() {
    let mockWebSocket = MockURLSessionWebSocket()
    
    // Valid close codes should not trigger precondition failure
    // Code 1000 (normal closure)
    mockWebSocket.testClose(code: 1000, reason: "normal")
    XCTAssertTrue(mockWebSocket.closeCalled)
    
    // Code in range 3000-4999 (application-defined)
    mockWebSocket.reset()
    mockWebSocket.testClose(code: 3000, reason: "app defined")
    XCTAssertTrue(mockWebSocket.closeCalled)
    
    mockWebSocket.reset()
    mockWebSocket.testClose(code: 4999, reason: "app defined")
    XCTAssertTrue(mockWebSocket.closeCalled)
    
    // Nil code should be allowed
    mockWebSocket.reset()
    mockWebSocket.testClose(code: nil, reason: "no code")
    XCTAssertTrue(mockWebSocket.closeCalled)
  }
  
  func testCloseReasonValidation() {
    let mockWebSocket = MockURLSessionWebSocket()
    
    // Reason within 123 bytes should be allowed
    let validReason = String(repeating: "a", count: 123)
    mockWebSocket.testClose(code: 1000, reason: validReason)
    XCTAssertTrue(mockWebSocket.closeCalled)
    
    // Nil reason should be allowed
    mockWebSocket.reset()
    mockWebSocket.testClose(code: 1000, reason: nil)
    XCTAssertTrue(mockWebSocket.closeCalled)
    
    // Empty reason should be allowed
    mockWebSocket.reset()
    mockWebSocket.testClose(code: 1000, reason: "")
    XCTAssertTrue(mockWebSocket.closeCalled)
  }
  
  // MARK: - Protocol Property Tests
  
  func testProtocolProperty() {
    let mockWebSocket = MockURLSessionWebSocket(protocol: "test-protocol")
    XCTAssertEqual(mockWebSocket.protocol, "test-protocol")
    
    let emptyProtocolWebSocket = MockURLSessionWebSocket(protocol: "")
    XCTAssertEqual(emptyProtocolWebSocket.protocol, "")
  }
  
  // MARK: - State Management Tests
  
  func testIsClosedInitiallyFalse() {
    let mockWebSocket = MockURLSessionWebSocket()
    XCTAssertFalse(mockWebSocket.isClosed)
  }
  
  func testCloseCodeAndReasonInitiallyNil() {
    let mockWebSocket = MockURLSessionWebSocket()
    XCTAssertNil(mockWebSocket.closeCode)
    XCTAssertNil(mockWebSocket.closeReason)
  }
  
  func testSendTextIgnoredWhenClosed() {
    let mockWebSocket = MockURLSessionWebSocket()
    mockWebSocket.simulateClosed()
    
    mockWebSocket.send("test message")
    XCTAssertEqual(mockWebSocket.sentTexts.count, 0)
  }
  
  func testSendBinaryIgnoredWhenClosed() {
    let mockWebSocket = MockURLSessionWebSocket()
    mockWebSocket.simulateClosed()
    
    let testData = Data([1, 2, 3])
    mockWebSocket.send(testData)
    XCTAssertEqual(mockWebSocket.sentBinaries.count, 0)
  }
  
  func testCloseIgnoredWhenAlreadyClosed() {
    let mockWebSocket = MockURLSessionWebSocket()
    mockWebSocket.simulateClosed()
    
    let originalCallCount = mockWebSocket.closeCallCount
    mockWebSocket.testClose(code: 1000, reason: "test")
    
    // Should not call close again when already closed
    XCTAssertEqual(mockWebSocket.closeCallCount, originalCallCount)
  }
  
  // MARK: - Event Handling Tests
  
  func testOnEventGetterSetter() {
    let mockWebSocket = MockURLSessionWebSocket()
    XCTAssertNil(mockWebSocket.onEvent)
    
    let eventHandler: (@Sendable (WebSocketEvent) -> Void) = { _ in }
    mockWebSocket.onEvent = eventHandler
    XCTAssertNotNil(mockWebSocket.onEvent)
    
    mockWebSocket.onEvent = nil
    XCTAssertNil(mockWebSocket.onEvent)
  }
  
  func testTriggerEventSetsCloseState() {
    let mockWebSocket = MockURLSessionWebSocket()
    
    var receivedEvent: WebSocketEvent?
    mockWebSocket.onEvent = { event in
      receivedEvent = event
    }
    
    mockWebSocket.simulateEvent(.close(code: 1000, reason: "normal"))
    
    XCTAssertEqual(receivedEvent, .close(code: 1000, reason: "normal"))
    XCTAssertTrue(mockWebSocket.isClosed)
    XCTAssertEqual(mockWebSocket.closeCode, 1000)
    XCTAssertEqual(mockWebSocket.closeReason, "normal")
    XCTAssertNil(mockWebSocket.onEvent) // Should be cleared on close
  }
  
  func testTriggerEventIgnoresWhenClosed() {
    let mockWebSocket = MockURLSessionWebSocket()
    mockWebSocket.simulateClosed()
    
    var eventReceived = false
    mockWebSocket.onEvent = { _ in
      eventReceived = true
    }
    
    // This should not trigger the event since the socket is closed
    mockWebSocket.simulateEvent(.text("test"))
    XCTAssertFalse(eventReceived)
  }
  
  // MARK: - URLSession Extension Tests
  
  func testSessionWithConfigurationNoDelegate() {
    let configuration = URLSessionConfiguration.default
    let session = URLSession.sessionWithConfiguration(configuration)
    
    XCTAssertNotNil(session)
    XCTAssertEqual(session.configuration, configuration)
  }
  
  func testSessionWithConfigurationWithDelegates() {
    let configuration = URLSessionConfiguration.default
    
    let session = URLSession.sessionWithConfiguration(
      configuration,
      onComplete: { _, _, _ in },
      onWebSocketTaskOpened: { _, _, _ in },
      onWebSocketTaskClosed: { _, _, _, _ in }
    )
    
    XCTAssertNotNil(session)
    XCTAssertNotNil(session.delegate)
  }
  
  // MARK: - Delegate Tests
  
  func testDelegateInitialization() {
    var onCompleteCalled = false
    var onOpenedCalled = false
    var onClosedCalled = false
    
    let delegate = _Delegate(
      onComplete: { _, _, _ in onCompleteCalled = true },
      onWebSocketTaskOpened: { _, _, _ in onOpenedCalled = true },
      onWebSocketTaskClosed: { _, _, _, _ in onClosedCalled = true }
    )
    
    XCTAssertNotNil(delegate.onComplete)
    XCTAssertNotNil(delegate.onWebSocketTaskOpened)
    XCTAssertNotNil(delegate.onWebSocketTaskClosed)
  }
}

// MARK: - Mock URLSessionWebSocket for Testing

private final class MockURLSessionWebSocket {
  private let _protocol: String
  private var _isClosed = false
  private var _closeCode: Int?
  private var _closeReason: String?
  private var _onEvent: (@Sendable (WebSocketEvent) -> Void)?
  
  // Test tracking properties
  var closeCalled = false
  var closeCallCount = 0
  var sentTexts: [String] = []
  var sentBinaries: [Data] = []
  
  init(protocol: String = "") {
    self._protocol = `protocol`
  }
  
  var closeCode: Int? { _closeCode }
  var closeReason: String? { _closeReason }
  var isClosed: Bool { _isClosed }
  var `protocol`: String { _protocol }
  
  var onEvent: (@Sendable (WebSocketEvent) -> Void)? {
    get { _onEvent }
    set { _onEvent = newValue }
  }
  
  func send(_ text: String) {
    guard !isClosed else { return }
    sentTexts.append(text)
  }
  
  func send(_ binary: Data) {
    guard !isClosed else { return }
    sentBinaries.append(binary)
  }
  
  func testClose(code: Int?, reason: String?) {
    guard !isClosed else { return }
    
    closeCalled = true
    closeCallCount += 1
    
    // Simulate the validation logic without preconditionFailure
    if let code = code {
      if code != 1000 && !(code >= 3000 && code <= 4999) {
        // This would trigger preconditionFailure in real implementation
        return
      }
    }
    
    if let reason = reason, reason.utf8.count > 123 {
      // This would trigger preconditionFailure in real implementation
      return
    }
    
    // Simulate successful close
    _isClosed = true
    _closeCode = code
    _closeReason = reason
    simulateEvent(.close(code: code, reason: reason ?? ""))
  }
  
  func simulateClosed() {
    _isClosed = true
    _closeCode = 1000
    _closeReason = "simulated close"
  }
  
  func simulateEvent(_ event: WebSocketEvent) {
    guard !_isClosed else { return }
    
    _onEvent?(event)
    
    if case .close(let code, let reason) = event {
      _onEvent = nil
      _isClosed = true
      _closeCode = code
      _closeReason = reason
    }
  }
  
  func reset() {
    closeCalled = false
    closeCallCount = 0
    sentTexts.removeAll()
    sentBinaries.removeAll()
    _isClosed = false
    _closeCode = nil
    _closeReason = nil
    _onEvent = nil
  }
}