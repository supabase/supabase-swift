import ConcurrencyExtras
import XCTest
@_spi(Internal) import _Helpers
@testable import Realtime

final class RealtimeClientTests: XCTestCase {
  private func makeSUT(
    headers: [String: String] = [:],
    params: [String: AnyJSON] = [:],
    vsn: String = Defaults.vsn
  ) -> (URL, RealtimeClient, PhoenixTransportMock) {
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
    let (url, sut, transport) = makeSUT()

    XCTAssertEqual(sut.url, url)
    XCTAssertEqual(
      sut.headers,
      ["X-Client-Info": "realtime-swift/\(_Helpers.version)"]
    )

    XCTAssertIdentical(sut.transport(url) as AnyObject, transport)
    let params = await sut.params
    XCTAssertEqual(params, [:])
    XCTAssertEqual(sut.vsn, Defaults.vsn)
  }

  func testInitializerWithCustomValues() async {
    let headers = ["Custom-Header": "Value"]
    let params = ["param1": AnyJSON.string("value1")]
    let vsn = "2.0"

    let (url, sut, transport) = makeSUT(headers: headers, params: params, vsn: vsn)

    XCTAssertEqual(sut.url, url)
    XCTAssertEqual(sut.headers["Custom-Header"], "Value")

    XCTAssertIdentical(sut.transport(url) as AnyObject, transport)

    let clientParam = await sut.params
    XCTAssertEqual(clientParam, params)
    XCTAssertEqual(sut.vsn, vsn)
  }

  func testInitializerWithAuthorizationJWT() async {
    let jwt = "your_jwt_token"
    let params = ["Authorization": AnyJSON.string("Bearer \(jwt)")]

    let (_, sut, _) = makeSUT(params: params)

    let accessToken = await sut.accessToken
    XCTAssertEqual(accessToken, jwt)
  }

  func testInitializerWithAPIKey() async {
    let url = URL(string: "https://example.com")!
    let apiKey = "your_api_key"
    let params = ["apikey": AnyJSON.string(apiKey)]

    let realtimeClient = RealtimeClient(url: url, params: params)

    let accessToken = await realtimeClient.accessToken
    XCTAssertEqual(accessToken, apiKey)
  }

  func testInitializerWithoutAccessToken() async {
    let params: [String: AnyJSON] = [:]
    let (_, sut, _) = makeSUT(params: params)

    let accessToken = await sut.accessToken
    XCTAssertNil(accessToken)
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

  func testConnect() async throws {
    let (_, sut, _) = makeSUT()

    await {
      let connection = await sut.connection
      XCTAssertNil(connection, "connection should be nil before calling connect method.")
    }()

    await sut.connect()
    let closeStatus = await sut.closeStatus
    XCTAssertEqual(closeStatus, .unknown)

    guard let connection = await sut.connection as? PhoenixTransportMock else {
      XCTFail("Expected a connection.")
      return
    }

    XCTAssertIdentical(connection.delegate, sut)

    XCTAssertEqual(connection.connectHeaders, sut.headers)

    // Given readyState = .open
    connection.readyState = .open

    // When calling connect
    await sut.connect()

    // Verify that transport's connect was called only once (first connect call).
    XCTAssertEqual(connection.connectCallCount, 1)
  }

  func testDisconnect() async {
    await withMainSerialExecutor {
      let timeoutTimer = TimeoutTimerMock()
      Dependencies.makeTimeoutTimer = { timeoutTimer }

      let heartbeatTimer = HeartbeatTimerMock()
      Dependencies.heartbeatTimer = { _ in
        heartbeatTimer
      }

      let (_, sut, transport) = makeSUT()

      let onCloseExpectation = expectation(description: "onClose")
      let onCloseReceivedParams = ActorIsolated<(Int, String?)?>(nil)
      await sut.onClose { code, reason in
        await onCloseReceivedParams.setValue((code, reason))
        onCloseExpectation.fulfill()
      }

      let onOpenExpectation = expectation(description: "onOpen")
      await sut.onOpen {
        onOpenExpectation.fulfill()
      }

      await sut.connect()
      var closeStatus = await sut.closeStatus
      XCTAssertEqual(closeStatus, .unknown)

      await fulfillment(of: [onOpenExpectation])

      await sut.disconnect(code: .normal, reason: "test")

      closeStatus = await sut.closeStatus
      XCTAssertEqual(closeStatus, .clean)

      let resetCallCount = await timeoutTimer.resetCallCount
      XCTAssertEqual(resetCallCount, 2)

      let connection = await sut.connection
      XCTAssertNil(connection)
      XCTAssertNil(transport.delegate)
      XCTAssertEqual(transport.disconnectCallCount, 1)
      XCTAssertEqual(transport.disconnectCode, 1000)
      XCTAssertEqual(transport.disconnectReason, "test")

      await fulfillment(of: [onCloseExpectation])

      guard let (code, reason) = await onCloseReceivedParams.value else {
        XCTFail("Expected onCloseReceivedParams")
        return
      }

      XCTAssertEqual(code, 1000)
      XCTAssertEqual(reason, "test")

      let stopCallCount = await heartbeatTimer.stopCallCount
      XCTAssertEqual(stopCallCount, 1)
    }
  }
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

    Task {
      await delegate?.onOpen(response: nil)
    }
  }

  func disconnect(code: Int, reason: String?) {
    disconnectCallCount += 1
    disconnectCode = code
    disconnectReason = reason

    Task {
      await delegate?.onClose(code: code, reason: reason)
    }
  }

  func send(data: Data) async {
    sendCallCount += 1
    sendData = data

    await delegate?.onMessage(message: data)
  }
}

actor TimeoutTimerMock: TimeoutTimerProtocol {
  func setHandler(_: @escaping @Sendable () async -> Void) async {}

  func setTimerCalculation(
    _: @escaping @Sendable (Int) async
      -> TimeInterval
  ) async {}

  private(set) var resetCallCount = 0
  private(set) var scheduleTimeoutCallCount = 0

  func reset() {
    resetCallCount += 1
  }

  func scheduleTimeout() {
    scheduleTimeoutCallCount += 1
  }
}

actor HeartbeatTimerMock: HeartbeatTimerProtocol {
  private(set) var startCallCount = 0
  private(set) var stopCallCount = 0
  private var eventHandler: (@Sendable () async -> Void)?

  func start(_ handler: @escaping @Sendable () async -> Void) async {
    startCallCount += 1
    eventHandler = handler
  }

  func stop() async {
    stopCallCount += 1
  }

  /// Helper method to simulate the timer firing an event
  func simulateTimerEvent() async {
    await eventHandler?()
  }
}
