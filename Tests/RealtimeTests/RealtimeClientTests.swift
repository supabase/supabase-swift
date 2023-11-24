import XCTest
@_spi(Internal) import _Helpers
@testable import Realtime

final class RealtimeClientTests: XCTestCase {
  func testInitializerWithDefaults() {
    let url = URL(string: "https://example.com")!
    let transport: (URL) -> PhoenixTransport = { _ in PhoenixTransportMock() }

    let realtimeClient = RealtimeClient(url: url, transport: transport)

    XCTAssertEqual(realtimeClient.url, url)
    XCTAssertEqual(
      realtimeClient.headers,
      ["X-Client-Info": "realtime-swift/\(_Helpers.version)"]
    )

    let transportInstance = realtimeClient.transport(url)
    XCTAssertTrue(transportInstance is PhoenixTransportMock)
    XCTAssertEqual(realtimeClient.params, [:])
    XCTAssertEqual(realtimeClient.vsn, Defaults.vsn)
  }

  func testInitializerWithCustomValues() {
    let url = URL(string: "https://example.com")!
    let headers = ["Custom-Header": "Value"]
    let transport: (URL) -> PhoenixTransport = { _ in PhoenixTransportMock() }
    let params = ["param1": AnyJSON.string("value1")]
    let vsn = "2.0"

    let realtimeClient = RealtimeClient(
      url: url,
      headers: headers,
      transport: transport,
      params: params,
      vsn: vsn
    )

    XCTAssertEqual(realtimeClient.url, url)
    XCTAssertEqual(realtimeClient.headers["Custom-Header"], "Value")

    let transportInstance = realtimeClient.transport(url)
    XCTAssertTrue(transportInstance is PhoenixTransportMock)

    XCTAssertEqual(realtimeClient.params, params)
    XCTAssertEqual(realtimeClient.vsn, vsn)
  }

  func testInitializerWithAuthorizationJWT() {
    let url = URL(string: "https://example.com")!
    let jwt = "your_jwt_token"
    let params = ["Authorization": AnyJSON.string("Bearer \(jwt)")]

    let realtimeClient = RealtimeClient(url: url, params: params)

    XCTAssertEqual(realtimeClient.accessToken, jwt)
  }

  func testInitializerWithAPIKey() {
    let url = URL(string: "https://example.com")!
    let apiKey = "your_api_key"
    let params = ["apikey": AnyJSON.string(apiKey)]

    let realtimeClient = RealtimeClient(url: url, params: params)

    XCTAssertEqual(realtimeClient.accessToken, apiKey)
  }

  func testInitializerWithoutAccessToken() {
    let url = URL(string: "https://example.com")!
    let params: [String: AnyJSON] = [:]

    let realtimeClient = RealtimeClient(url: url, params: params)

    XCTAssertNil(realtimeClient.accessToken)
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
}

final class PhoenixTransportMock: PhoenixTransport {
  var readyState: Realtime.PhoenixTransportReadyState = .closed

  var delegate: Realtime.PhoenixTransportDelegate?

  func connect(with _: [String: String]) {}

  func disconnect(code _: Int, reason _: String?) {}

  func send(data _: Data) {}
}
