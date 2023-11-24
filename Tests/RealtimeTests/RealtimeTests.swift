import XCTest

@testable import Realtime

final class RealtimeTests: XCTestCase {
  private func makeSUT(file: StaticString = #file, line: UInt = #line) -> RealtimeClient {
    let sut = RealtimeClient(
      url: URL(string: "https://nixfbjgqturwbakhnwym.supabase.co/realtime/v1")!,
      params: [
        "apikey": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5peGZiamdxdHVyd2Jha2hud3ltIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NzAzMDE2MzksImV4cCI6MTk4NTg3NzYzOX0.Ct6W75RPlDM37TxrBQurZpZap3kBy0cNkUimxF50HSo",
      ]
    )
    addTeardownBlock { [weak sut] in
      XCTAssertNil(sut, "RealtimeClient leaked.", file: file, line: line)
    }
    return sut
  }

  func testConnection() async {
    let sut = makeSUT()

    let onOpenExpectation = expectation(description: "onOpen")
    sut.onOpen { [weak sut] in
      onOpenExpectation.fulfill()
      sut?.disconnect()
    }

    sut.onError { error, _ in
      XCTFail("connection failed with: \(error)")
    }

    let onCloseExpectation = expectation(description: "onClose")
    onCloseExpectation.assertForOverFulfill = false
    sut.onClose {
      onCloseExpectation.fulfill()
    }

    sut.connect()

    await fulfillment(of: [onOpenExpectation, onCloseExpectation])
  }

  func testOnChannelEvent() async {
    let sut = makeSUT()

    sut.connect()
    defer { sut.disconnect() }

    let expectation = expectation(description: "subscribe")
    expectation.expectedFulfillmentCount = 2

    var channel: RealtimeChannel?
    addTeardownBlock { [weak channel] in
      XCTAssertNil(channel)
    }

    var states: [RealtimeSubscribeStates] = []
    channel = sut
      .channel("public")
      .subscribe { state, error in
        states.append(state)

        if let error {
          XCTFail("Error subscribing to channel: \(error)")
        }

        expectation.fulfill()

        if state == .subscribed {
          channel?.unsubscribe()
        }
      }

    await fulfillment(of: [expectation])
    XCTAssertEqual(states, [.subscribed, .closed])
  }
}
