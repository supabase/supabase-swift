import Foundation
import HTTPTypes
import Mocker
import TestHelpers
import Testing

@testable import Functions

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite(.serialized, .mockerSerialized)
struct FunctionsV3APITests {
  let url = URL(string: "http://localhost:5432/functions/v1")!

  private func makeSUT() -> FunctionsClient {
    Mocker.removeAll()

    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [MockingURLProtocol.self]
    let session = URLSession(configuration: sessionConfiguration)
    return FunctionsClient(
      url: url,
      headers: ["apikey": "key"],
      region: nil,
      fetch: { try await session.data(for: $0) },
      sessionConfiguration: sessionConfiguration
    )
  }

  @Test
  func functionBodyFactories() throws {
    let json = try FunctionBody.json(["name": "Supabase"])
    #expect(json.contentType == "application/json")
    #expect(String(bytes: json.data, encoding: .utf8) == #"{"name":"Supabase"}"#)

    let text = FunctionBody.text("hello")
    #expect(text.contentType == "text/plain; charset=utf-8")
    #expect(text.data == Data("hello".utf8))

    #expect(FunctionBody.data(Data([1])).contentType == "application/octet-stream")
    #expect(FunctionBody.data(Data([1]), contentType: "image/png").contentType == "image/png")
  }

  @Test
  func optionsDefaults() {
    let options = FunctionInvokeOptions()
    #expect(options.method == .post)
    #expect(options.headers.isEmpty)
    #expect(options.query.isEmpty)
    #expect(options.region == nil)
    #expect(options.timeout == nil)
  }

  @Test
  func invokeSendsBodyHeadersMethodQueryAndRegion() async throws {
    let sut = makeSUT()
    let captured = LockedBox<URLRequest?>(nil)

    var mock = Mock(
      url: url.appendingPathComponent("echo"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.put: Data(#"{"ok":true}"#.utf8)],
      additionalHeaders: [
        "x-sb-edge-region": "us-east-1",
        "x-deno-execution-id": "exec-1",
        "sb-request-id": "req-1",
        "Content-Type": "application/json",
      ]
    )
    mock.onRequestHandler = OnRequestHandler { request in captured.value = request }
    mock.register()

    let response = try await sut.invoke(
      "echo",
      body: .json(["a": 1]),
      options: .init(
        method: .put,
        headers: [HTTPField.Name("X-Custom")!: "v"],
        query: [URLQueryItem(name: "k", value: "v")],
        region: .usEast1,
        timeout: .seconds(30)
      )
    )

    #expect(response.status.code == 200)
    #expect(response.contentType == "application/json")
    #expect(response.region == .usEast1)
    #expect(response.executionID == "exec-1")
    #expect(response.requestID == "req-1")
    #expect(response.text == #"{"ok":true}"#)

    let request = try #require(captured.value)
    #expect(request.httpMethod == "PUT")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.value(forHTTPHeaderField: "X-Custom") == "v")
    #expect(request.value(forHTTPHeaderField: "x-region") == "us-east-1")
    #expect(request.timeoutInterval == 30)
    let items = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?
      .queryItems
    #expect(items?.contains(URLQueryItem(name: "k", value: "v")) == true)
    #expect(items?.contains(URLQueryItem(name: "forceFunctionRegion", value: "us-east-1")) == true)
  }

  @Test
  func invokeDecodes() async throws {
    let sut = makeSUT()
    Mock(
      url: url.appendingPathComponent("hello"),
      statusCode: 200,
      data: [.post: Data(#"{"message":"hi"}"#.utf8)]
    ).register()

    struct Payload: Decodable { var message: String }
    let payload: Payload = try await sut.invoke("hello")
    #expect(payload.message == "hi")

    let viaResponse = try await sut.invoke("hello").decode(as: Payload.self)
    #expect(viaResponse.message == "hi")
  }

  @Test
  func invokeThrowsServerKind() async throws {
    let sut = makeSUT()
    Mock(url: url.appendingPathComponent("boom"), statusCode: 500, data: [.post: Data("x".utf8)])
      .register()

    do {
      try await sut.invoke("boom")
      Issue.record("should throw")
    } catch let error as FunctionsError {
      #expect(error.kind == .server)
      #expect(error.statusCode == 500)
    }
  }

  @Test
  func invokeThrowsRelayKind() async throws {
    let sut = makeSUT()
    Mock(
      url: url.appendingPathComponent("relay"), statusCode: 200, data: [.post: Data()],
      additionalHeaders: ["x-relay-error": "true"]
    ).register()

    do {
      try await sut.invoke("relay")
      Issue.record("should throw")
    } catch let error as FunctionsError {
      #expect(error.kind == .relay)
      #expect(error.statusCode == nil)
    }
  }

  @Test
  func streamReturnsHeadAndBody() async throws {
    let sut = makeSUT()
    Mock(
      url: url.appendingPathComponent("stream"),
      statusCode: 200,
      data: [.post: Data("hello world".utf8)],
      additionalHeaders: ["x-sb-edge-region": "eu-west-1"]
    ).register()

    let response = try await sut.stream("stream", body: .text("go"))
    #expect(response.status.code == 200)
    #expect(response.region == .euWest1)

    var received = Data()
    for try await chunk in response.body { received.append(chunk) }
    #expect(String(bytes: received, encoding: .utf8) == "hello world")
  }

  @Test
  func streamThrowsOnServerError() async throws {
    let sut = makeSUT()
    Mock(url: url.appendingPathComponent("stream"), statusCode: 502, data: [.post: Data()])
      .register()

    do {
      _ = try await sut.stream("stream")
      Issue.record("should throw")
    } catch let error as FunctionsError {
      #expect(error.kind == .server)
      #expect(error.statusCode == 502)
    }
  }

  @Test
  func streamThrowsOnRelayError() async throws {
    let sut = makeSUT()
    Mock(
      url: url.appendingPathComponent("stream"), statusCode: 200, data: [.post: Data()],
      additionalHeaders: ["x-relay-error": "true"]
    ).register()

    do {
      _ = try await sut.stream("stream")
      Issue.record("should throw")
    } catch let error as FunctionsError {
      #expect(error.kind == .relay)
    }
  }

  @Test
  func regionConstants() {
    #expect(FunctionRegion.euCentral2.rawValue == "eu-central-2")
    let literal: FunctionRegion = "custom"
    #expect(literal.rawValue == "custom")
  }
}

private final class LockedBox<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var _value: Value
  init(_ value: Value) { _value = value }
  var value: Value {
    get { lock.withLock { _value } }
    set { lock.withLock { _value = newValue } }
  }
}
