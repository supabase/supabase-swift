import ConcurrencyExtras
import XCTest
import XCTestDynamicOverlay
@_spi(Internal) import _Helpers
@testable import Realtime

final class RealtimeClientTests: XCTestCase {
  var timeoutTimer: TimeoutTimer = .unimplemented
  var heartbeatTimer = HeartbeatTimer.unimplemented

  private func makeSUT(
    headers: [String: String] = [:],
    params: [String: AnyJSON] = [:],
    vsn: String = Defaults.vsn
  ) -> (URL, RealtimeClient, PhoenixTransportMock) {
    Dependencies.makeTimeoutTimer = { self.timeoutTimer }
    Dependencies.makeHeartbeatTimer = { _ in self.heartbeatTimer }

    let url = URL(string: "https://example.com")!
    let transport = PhoenixTransportMock()
    let sut = RealtimeClient(
      url: url,
      headers: headers,
      transport: { _ in transport },
      params: params,
      vsn: vsn
    )
    return (url, sut, transport)
  }

  func testInitializerWithDefaults() async {
    timeoutTimer.handler = { _ in }
    timeoutTimer.timerCalculation = { _ in }

    let (url, sut, transport) = makeSUT()

    XCTAssertEqual(sut.url, url)
    XCTAssertEqual(
      sut.headers,
      ["X-Client-Info": "realtime-swift/\(_Helpers.version)"]
    )

    XCTAssertIdentical(sut.transport(url) as AnyObject, transport)
    XCTAssertEqual(sut.params, [:])
    XCTAssertEqual(sut.vsn, Defaults.vsn)
  }

  func testInitializerWithCustomValues() async {
    timeoutTimer.handler = { _ in }
    timeoutTimer.timerCalculation = { _ in }

    let headers = ["Custom-Header": "Value"]
    let params = ["param1": AnyJSON.string("value1")]
    let vsn = "2.0"

    let (url, sut, transport) = makeSUT(headers: headers, params: params, vsn: vsn)

    XCTAssertEqual(sut.url, url)
    XCTAssertEqual(sut.headers["Custom-Header"], "Value")

    XCTAssertIdentical(sut.transport(url) as AnyObject, transport)

    XCTAssertEqual(sut.params, params)
    XCTAssertEqual(sut.vsn, vsn)
  }

  func testInitializerWithAuthorizationJWT() async {
    timeoutTimer.handler = { _ in }
    timeoutTimer.timerCalculation = { _ in }

    let jwt = "your_jwt_token"
    let params = ["Authorization": AnyJSON.string("Bearer \(jwt)")]

    let (_, sut, _) = makeSUT(params: params)

    XCTAssertEqual(sut.accessToken, jwt)
  }

  func testInitializerWithAPIKey() async {
    timeoutTimer.handler = { _ in }
    timeoutTimer.timerCalculation = { _ in }

    let url = URL(string: "https://example.com")!
    let apiKey = "your_api_key"
    let params = ["apikey": AnyJSON.string(apiKey)]

    let realtimeClient = RealtimeClient(url: url, params: params)

    XCTAssertEqual(realtimeClient.accessToken, apiKey)
  }

  func testInitializerWithoutAccessToken() async {
    timeoutTimer.handler = { _ in }
    timeoutTimer.timerCalculation = { _ in }

    let params: [String: AnyJSON] = [:]
    let (_, sut, _) = makeSUT(params: params)

    XCTAssertNil(sut.accessToken)
  }

  func testBuildEndpointUrl() {
    let baseUrl = URL(string: "https://example.com")!
    let params = ["param1": AnyJSON.string("value1"), "param2": .number(123)]
    let vsn = "1.0"

    let resultUrl = RealtimeClient.buildEndpointUrl(url: baseUrl, params: params, vsn: vsn)

    XCTAssertEqual(resultUrl.scheme, "https")
    XCTAssertEqual(resultUrl.host, "example.com")
    XCTAssertEqual(resultUrl.path, "/websocket")

    XCTAssertTrue(resultUrl.query!.contains("vsn=1.0"))
    XCTAssertTrue(resultUrl.query!.contains("param1=value1"))
    XCTAssertTrue(resultUrl.query!.contains("param2=123"))
  }

  func testBuildEndpointUrlWithoutParams() {
    let baseUrl = URL(string: "https://example.com")!
    let params: [String: Any] = [:]
    let vsn = "1.0"

    let resultUrl = RealtimeClient.buildEndpointUrl(url: baseUrl, params: params, vsn: vsn)

    XCTAssertEqual(resultUrl.scheme, "https")
    XCTAssertEqual(resultUrl.host, "example.com")
    XCTAssertEqual(resultUrl.path, "/websocket")

    XCTAssertEqual(resultUrl.query, "vsn=1.0")
  }

  func testConnect() throws {
    timeoutTimer.handler = { _ in }
    timeoutTimer.timerCalculation = { _ in }
    timeoutTimer.reset = {}

    let heartbeatStartCallCount = LockIsolated(0)
    heartbeatTimer.start = { _ in
      heartbeatStartCallCount.withValue {
        $0 += 1
      }
    }

    let (_, sut, _) = makeSUT()

    XCTAssertNil(sut.connection, "connection should be nil before calling connect method.")

    sut.connect()
    XCTAssertEqual(sut.closeStatus, .unknown)

    let connection = try XCTUnwrap(sut.connection as? PhoenixTransportMock)

    XCTAssertIdentical(connection.delegate, sut)

    XCTAssertEqual(connection.connectHeaders, sut.headers)

    // Given readyState = .open
    connection.readyState = .open

    // When calling connect
    sut.connect()

    // Verify that transport's connect was called only once (first connect call).
    XCTAssertEqual(connection.connectCallCount, 1)
    XCTAssertEqual(heartbeatStartCallCount.value, 1)
  }

  func testDisconnect() async throws {
    timeoutTimer.handler = { _ in }
    timeoutTimer.timerCalculation = { _ in }

    let timerResetCallCount = LockIsolated(0)

    timeoutTimer.reset = {
      timerResetCallCount.withValue { $0 += 1 }
    }

    let heartbeatStartCallCount = LockIsolated(0)
    heartbeatTimer.start = { _ in
      heartbeatStartCallCount.withValue { $0 += 1 }
    }

    heartbeatTimer.stop = {}

    let (_, sut, transport) = makeSUT()

    let onCloseExpectation = expectation(description: "onClose")
    let onCloseReceivedParams = LockIsolated<(Int, String?)?>(nil)
    sut.onClose { code, reason in
      onCloseReceivedParams.setValue((code, reason))
      onCloseExpectation.fulfill()
    }

    let onOpenExpectation = expectation(description: "onOpen")
    sut.onOpen {
      onOpenExpectation.fulfill()
    }

    sut.connect()
    XCTAssertEqual(sut.closeStatus, .unknown)

    await fulfillment(of: [onOpenExpectation])

    sut.disconnect(code: .normal, reason: "test")

    XCTAssertEqual(sut.closeStatus, .clean)

    XCTAssertEqual(timerResetCallCount.value, 2)

    XCTAssertNil(sut.connection)
    XCTAssertNil(transport.delegate)
    XCTAssertEqual(transport.disconnectCallCount, 1)
    XCTAssertEqual(transport.disconnectCode, 1000)
    XCTAssertEqual(transport.disconnectReason, "test")

    await fulfillment(of: [onCloseExpectation])

    let (code, reason) = try XCTUnwrap(onCloseReceivedParams.value)

    XCTAssertEqual(code, 1000)
    XCTAssertEqual(reason, "test")

    XCTAssertEqual(heartbeatStartCallCount.value, 1)
  }
}

extension HeartbeatTimer {
  static let unimplemented = Self(
    start: XCTestDynamicOverlay.unimplemented("\(Self.self).start"),
    stop: XCTestDynamicOverlay.unimplemented("\(Self.self).stop")
  )

  static let noop = Self(
    start: { _ in },
    stop: {}
  )
}

extension TimeoutTimer {
  static let unimplemented = Self(
    handler: XCTestDynamicOverlay.unimplemented("\(Self.self).handler"),
    timerCalculation: XCTestDynamicOverlay.unimplemented("\(Self.self).timerCalculation"),
    reset: XCTestDynamicOverlay.unimplemented("\(Self.self).reset"),
    scheduleTimeout: XCTestDynamicOverlay.unimplemented("\(Self.self).scheduleTimeout")
  )

  static let noop = Self(
    handler: { _ in },
    timerCalculation: { _ in },
    reset: {},
    scheduleTimeout: {}
  )
}

class PhoenixTransportMock: PhoenixTransport {
  var readyState: PhoenixTransportReadyState = .closed
  var delegate: PhoenixTransportDelegate?

  private(set) var connectCallCount = 0
  private(set) var disconnectCallCount = 0
  private(set) var sendCallCount = 0

  private(set) var connectHeaders: [String: String]?
  private(set) var disconnectCode: Int?
  private(set) var disconnectReason: String?
  private(set) var sendData: Data?

  func connect(with headers: [String: String]) {
    connectCallCount += 1
    connectHeaders = headers

    delegate?.onOpen(response: nil)
  }

  func disconnect(code: Int, reason: String?) {
    disconnectCallCount += 1
    disconnectCode = code
    disconnectReason = reason

    delegate?.onClose(code: code, reason: reason)
  }

  func send(data: Data) {
    sendCallCount += 1
    sendData = data

    delegate?.onMessage(message: data)
  }
}
