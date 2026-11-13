import Foundation
import HTTPTypes
import Helpers
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
  func responsesCanBeBuiltForTestsAndMocks() async throws {
    let headers: HTTPFields = [.contentType: "application/json"]

    let response = FunctionResponse(status: .ok, headers: headers, body: Data(#"{"id":1}"#.utf8))
    #expect(response.status == .ok)
    #expect(response.contentType == "application/json")
    #expect(try response.decode(as: [String: Int].self) == ["id": 1])

    let stream = FunctionStreamResponse(
      status: .ok,
      headers: headers,
      body: AsyncThrowingStream { continuation in
        continuation.yield(Data("chunk".utf8))
        continuation.finish()
      }
    )
    var chunks: [Data] = []
    for try await chunk in stream.body { chunks.append(chunk) }
    #expect(stream.contentType == "application/json")
    #expect(chunks == [Data("chunk".utf8)])
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
    let captured = CapturedRequest()

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
    mock.onRequestHandler = captured.handler
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

    let request = try #require(captured.request)
    #expect(captured.body == Data(#"{"a":1}"#.utf8))
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
  func v2CallFormsKeepTheVoidOverload() async throws {
    let sut = makeSUT()
    Mock(url: url.appendingPathComponent("fn"), statusCode: 200, data: [.post: Data("ok".utf8)])
      .register()

    var tasks: Set<Task<Void, any Error>> = []
    let task = Task { try await sut.invoke("fn") }
    tasks.insert(task)
    let _: Void = try await task.value

    func run(_ work: () async throws -> Void) async rethrows { try await work() }
    let work = { try await sut.invoke("fn") }
    try await run(work)

    try? await sut.invoke("fn")

    let withOptions = Task { try await sut.invoke("fn", options: FunctionInvokeOptions()) }
    tasks.insert(withOptions)
    try await withOptions.value

    #expect(tasks.count == 2)
  }

  @Test
  func v3CallFormsSelectTheResponseOverload() async throws {
    let sut = makeSUT()
    Mock(url: url.appendingPathComponent("fn"), statusCode: 200, data: [.post: Data("ok".utf8)])
      .register()

    let annotated: FunctionResponse = try await sut.invoke("fn")
    #expect(annotated.text == "ok")

    let coerced = try await sut.invoke("fn") as FunctionResponse
    #expect(coerced.status == .ok)

    let withBody = try await sut.invoke("fn", body: .json(["a": 1]))
    #expect(withBody.text == "ok")

    let withBodyAndOptions = try await sut.invoke(
      "fn", body: .json(["a": 1]), options: FunctionInvokeOptions(method: .post))
    #expect(withBodyAndOptions.text == "ok")

    let withNilBody = try await sut.invoke("fn", body: nil, options: FunctionInvokeOptions())
    #expect(withNilBody.text == "ok")

    #expect(try await sut.invoke("fn").text == "ok")

    try await sut.invoke("fn", body: .text("discarded result"))
  }

  @Test
  func invokeThrowsServerKind() async throws {
    let sut = makeSUT()
    Mock(url: url.appendingPathComponent("boom"), statusCode: 500, data: [.post: Data("x".utf8)])
      .register()

    do {
      let _: FunctionResponse = try await sut.invoke("boom")
      Issue.record("should throw")
    } catch let error as FunctionsError {
      #expect(error.kind == .server)
      guard case .httpError(code: 500, _) = error else {
        Issue.record("unexpected error: \(error)")
        return
      }
      #expect(error.message == "Edge Function returned a non-2xx status code: 500")
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
      let _: FunctionResponse = try await sut.invoke("relay")
      Issue.record("should throw")
    } catch let error as FunctionsError {
      #expect(error.kind == .relay)
      #expect(error.message == "Relay Error invoking the Edge Function")
    }
  }

  @Test
  func streamReturnsHeadAndBody() async throws {
    let sut = makeSUT()
    let captured = CapturedRequest()
    var mock = Mock(
      url: url.appendingPathComponent("stream"),
      statusCode: 200,
      data: [.post: Data("hello world".utf8)],
      additionalHeaders: ["x-sb-edge-region": "eu-west-1"]
    )
    mock.onRequestHandler = captured.handler
    mock.register()

    let response = try await sut.stream("stream", body: .text("go"))
    #expect(captured.body == Data("go".utf8))
    #expect(
      captured.request?.value(forHTTPHeaderField: "Content-Type") == "text/plain; charset=utf-8")
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
      guard case .httpError(code: 502, _) = error else {
        Issue.record("unexpected error: \(error)")
        return
      }
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
  func streamThrowsTransportErrorBeforeHead() async throws {
    let sut = makeSUT()
    Mock(
      url: url.appendingPathComponent("stream"), statusCode: 200, data: [.post: Data()],
      requestError: URLError(.notConnectedToInternet)
    ).register()

    do {
      _ = try await sut.stream("stream")
      Issue.record("should throw")
    } catch let error as URLError {
      #expect(error.code == .notConnectedToInternet)
    }
  }

  @Test
  func streamThrowsCancellationErrorWhenCancelledBeforeHead() async throws {
    let sut = makeSUT()
    var mock = Mock(
      url: url.appendingPathComponent("slow"), statusCode: 200, data: [.post: Data("late".utf8)])
    mock.delay = .seconds(2)
    mock.register()

    let task = Task { try await sut.stream("slow") }
    task.cancel()

    await #expect(throws: CancellationError.self) {
      _ = try await task.value
    }
  }

  @Test
  func optionsContentTypeOverridesBodyContentType() async throws {
    let sut = makeSUT()
    let captured = CapturedRequest()
    var mock = Mock(
      url: url.appendingPathComponent("echo"), statusCode: 200, data: [.post: Data()])
    mock.onRequestHandler = captured.handler
    mock.register()

    try await sut.invoke(
      "echo",
      body: .json(["a": 1]),
      options: .init(headers: [.contentType: "application/vnd.custom+json"])
    )

    #expect(
      captured.request?.value(forHTTPHeaderField: "Content-Type") == "application/vnd.custom+json")
    #expect(captured.body == Data(#"{"a":1}"#.utf8))
  }

  @Test
  func functionBodyContentTypeWinsOverDeprecatedBodyInitializerDefault() async throws {
    let sut = makeSUT()
    let captured = CapturedRequest()
    var mock = Mock(
      url: url.appendingPathComponent("echo"), statusCode: 200, data: [.post: Data()])
    mock.onRequestHandler = captured.handler
    mock.register()

    try await sut.invoke(
      "echo",
      body: .text("new-body"),
      options: FunctionInvokeOptions(body: ["old": "body"])
    )

    #expect(
      captured.request?.value(forHTTPHeaderField: "Content-Type") == "text/plain; charset=utf-8")
    #expect(captured.body == Data("new-body".utf8))
  }

  @Test
  func callerContentTypeOnDeprecatedBodyInitializerWinsOverFunctionBody() async throws {
    let sut = makeSUT()
    let captured = CapturedRequest()
    var mock = Mock(
      url: url.appendingPathComponent("echo"), statusCode: 200, data: [.post: Data()])
    mock.onRequestHandler = captured.handler
    mock.register()

    try await sut.invoke(
      "echo",
      body: .text("new-body"),
      options: FunctionInvokeOptions(
        headers: ["content-type": "application/json"], body: ["old": "body"])
    )

    #expect(captured.request?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(captured.body == Data("new-body".utf8))
  }

  @Test
  func deprecatedBodyInitializerStillSendsItsBodyAndContentType() async throws {
    let sut = makeSUT()
    let captured = CapturedRequest()
    var mock = Mock(
      url: url.appendingPathComponent("echo"), statusCode: 200, data: [.post: Data()])
    mock.onRequestHandler = captured.handler
    mock.register()

    try await sut.invoke("echo", options: FunctionInvokeOptions(body: "old-body"))

    #expect(captured.request?.value(forHTTPHeaderField: "Content-Type") == "text/plain")
    #expect(captured.body == Data("old-body".utf8))
  }

  @Test(arguments: [TimeInterval.infinity, .greatestFiniteMagnitude, 1e20, -1e20])
  func deprecatedTimeoutIntervalKeepsValuesDurationCannotHold(timeoutInterval: TimeInterval) {
    let sut = makeSUT()

    let options = [
      FunctionInvokeOptions(timeoutInterval: timeoutInterval),
      FunctionInvokeOptions(region: FunctionRegion.usEast1, timeoutInterval: timeoutInterval),
      FunctionInvokeOptions(body: "b", timeoutInterval: timeoutInterval),
      FunctionInvokeOptions(
        region: FunctionRegion.usEast1, body: "b", timeoutInterval: timeoutInterval),
    ]

    for options in options {
      let request = sut.buildRequest(functionName: "fn", body: nil, options: options)
      #expect(request.timeoutInterval == timeoutInterval)
    }
  }

  @Test
  func deprecatedTimeoutIntervalKeepsNaN() {
    let sut = makeSUT()
    let options = FunctionInvokeOptions(timeoutInterval: .nan)
    let request = sut.buildRequest(functionName: "fn", body: nil, options: options)
    #expect(request.timeoutInterval.isNaN)
    #expect(options.timeout == nil)
  }

  @Test
  func deprecatedTimeoutIntervalIsReadableAsTimeoutAndReplaceable() {
    let sut = makeSUT()

    var options = FunctionInvokeOptions(timeoutInterval: 12.5)
    #expect(options.timeout == .milliseconds(12500))
    #expect(
      sut.buildRequest(functionName: "fn", body: nil, options: options).timeoutInterval == 12.5)
    #expect(options == FunctionInvokeOptions(timeout: .milliseconds(12500)))

    options = FunctionInvokeOptions(timeoutInterval: .infinity)
    #expect(options.timeout != nil)
    options.timeout = .seconds(5)
    #expect(sut.buildRequest(functionName: "fn", body: nil, options: options).timeoutInterval == 5)

    options.timeout = nil
    #expect(
      sut.buildRequest(functionName: "fn", body: nil, options: options).timeoutInterval
        == FunctionsClient.requestIdleTimeout)
  }

  @Test
  func regionConstants() {
    #expect(FunctionRegion.euCentral2.rawValue == "eu-central-2")
    let literal: FunctionRegion = "custom"
    #expect(literal.rawValue == "custom")
  }
}

private final class CapturedRequest: @unchecked Sendable {
  private let lock = NSLock()
  private var _request: URLRequest?
  private var _body: Data?

  var request: URLRequest? { lock.withLock { _request } }
  var body: Data? { lock.withLock { _body } }

  var handler: OnRequestHandler {
    OnRequestHandler { request in
      let body = request.httpBody ?? request.httpBodyStream.map(Self.read)
      self.lock.withLock {
        self._request = request
        self._body = body
      }
    }
  }

  private static func read(_ stream: InputStream) -> Data {
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count > 0 else { break }
      data.append(buffer, count: count)
    }
    return data
  }
}
