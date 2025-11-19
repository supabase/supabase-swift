//
//  ConnectionManagerTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 19/11/25.
//

import ConcurrencyExtras
import XCTest

@testable import Realtime

final class ConnectionManagerTests: XCTestCase {
  let url = URL(string: "ws://localhost")!
  let headers = ["apikey": "key"]

  var sut: ConnectionManager!
  var ws: FakeWebSocket!
  var transportCallCount = 0
  var lastConnectURL: URL?
  var lastConnectHeaders: [String: String]?

  override func setUp() {
    super.setUp()

    transportCallCount = 0
    lastConnectURL = nil
    lastConnectHeaders = nil
    (ws, _) = FakeWebSocket.fakes()
  }

  override func tearDown() {
    sut = nil
    ws = nil
    super.tearDown()
  }

  private func makeSUT(
    url: URL = URL(string: "ws://localhost")!,
    headers: [String: String] = [:],
    reconnectDelay: TimeInterval = 0.1
  ) -> ConnectionManager {
    ConnectionManager(
      transport: { url, headers in
        self.transportCallCount += 1
        self.lastConnectURL = url
        self.lastConnectHeaders = headers
        return self.ws!
      },
      url: url,
      headers: headers,
      reconnectDelay: reconnectDelay,
      logger: nil
    )
  }

  func testConnect() async throws {
    sut = makeSUT()

    let isConnectingExpectation = self.expectation(description: "connecting state")

    Task {
      _ = await sut.stateChanges.first { $0.isConnecting }
      isConnectingExpectation.fulfill()
    }

    var isConnected = await sut.isConnected
    XCTAssertFalse(isConnected)
    try await sut.connect()

    isConnected = await sut.isConnected
    XCTAssertTrue(isConnected)

    await fulfillment(of: [isConnectingExpectation], timeout: 1)
  }

}
