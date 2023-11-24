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

  func testInitializerWithDefaults() {
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

  func testInitializerWithCustomValues() {
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

  func testInitializerWithAuthorizationJWT() {
    let jwt = "your_jwt_token"
    let params = ["Authorization": AnyJSON.string("Bearer \(jwt)")]

    let (_, sut, _) = makeSUT(params: params)

    XCTAssertEqual(sut.accessToken, jwt)
  }

  func testInitializerWithAPIKey() {
    let url = URL(string: "https://example.com")!
    let apiKey = "your_api_key"
    let params = ["apikey": AnyJSON.string(apiKey)]

    let realtimeClient = RealtimeClient(url: url, params: params)

    XCTAssertEqual(realtimeClient.accessToken, apiKey)
  }

  func testInitializerWithoutAccessToken() {
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
}

final class PhoenixTransportMock: PhoenixTransport {
  var readyState: Realtime.PhoenixTransportReadyState = .closed

  var delegate: Realtime.PhoenixTransportDelegate?

  func connect(with _: [String: String]) {}

  func disconnect(code _: Int, reason _: String?) {}

  func send(data _: Data) {}
}
