import ConcurrencyExtras
import Foundation
import Mocker
import Testing

@testable import Functions

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// MARK: - Test Helpers

/// A mock RequestAdapter for testing request adaptation.
struct MockRequestAdapter: RequestAdapter {
  let transform: @Sendable (URLRequest) async throws -> URLRequest

  func adapt(_ request: URLRequest) async throws -> URLRequest {
    try await transform(request)
  }
}

/// A mock ResponseInterceptor for testing response interception.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
struct MockResponseInterceptor: ResponseInterceptor {
  let transform:
    @Sendable (ResponseBody, HTTPURLResponse) async throws -> (
      ResponseBody, HTTPURLResponse
    )

  func intercept(body: ResponseBody, response: HTTPURLResponse) async throws
    -> (
      ResponseBody, HTTPURLResponse
    )
  {
    try await transform(body, response)
  }
}

// MARK: - Tests

@Suite(.serialized)
struct FunctionsClientV2Tests {
  let baseURL = URL(string: "http://localhost:54321/functions/v1")!
  let apiKey =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"

  func makeClient() -> FunctionsClientV2 {
    let config = URLSessionConfiguration.default
    config.protocolClasses = [MockingURLProtocol.self]

    return FunctionsClientV2(
      baseURL: baseURL,
      sessionConfiguration: config,
      headers: ["apikey": apiKey]
    )
  }

  // deinit {
  //   Mocker.removeAll()
  // }

  // MARK: - Initialization Tests

  @Test("Client initialization with URL and headers")
  func testInitialization() async {
    let client = FunctionsClientV2(
      url: baseURL,
      headers: ["apikey": apiKey, "Custom-Header": "value"]
    )

    #expect(await client.url == URL(string: baseURL.absoluteString + "/")!)
    #expect(await client.headers["apikey"] == apiKey)
    #expect(await client.headers["Custom-Header"] == "value")
    #expect(await client.headers["X-Client-Info"] != nil)
  }

  @Test("Client initialization with region")
  func testInitializationWithRegion() async {
    let client = FunctionsClientV2(
      url: baseURL,
      headers: ["apikey": apiKey],
      region: .usEast1
    )

    #expect(await client.url == URL(string: baseURL.absoluteString + "/")!)
  }

  // MARK: - Authentication Tests

  @Test("setAuth adds Authorization header")
  func testSetAuth() async {
    let client = FunctionsClientV2(
      url: baseURL,
      headers: ["apikey": apiKey]
    )

    await client.setAuth("test-token")
    #expect(await client.headers["Authorization"] == "Bearer test-token")
  }

  @Test("setAuth with nil removes Authorization header")
  func testSetAuthWithNil() async {
    let client = FunctionsClientV2(
      url: baseURL,
      headers: ["apikey": apiKey]
    )

    await client.setAuth("test-token")
    #expect(await client.headers["Authorization"] == "Bearer test-token")

    await client.setAuth(nil)
    #expect(await client.headers["Authorization"] == nil)
  }

  // MARK: - Basic Invocation Tests

  @Test("invoke returns raw data and response")
  func testInvokeRawData() async throws {
    let responseData = Data("{\"message\":\"Hello, world!\"}".utf8)

    Mock(
      url: baseURL.appendingPathComponent("hello"),
      statusCode: 200,
      data: [.post: responseData]
    ).register()

    let client = makeClient()
    let (data, response) = try await client.invoke("hello")

    #expect(response.statusCode == 200)
    #expect(data == responseData)

    let json =
      try JSONSerialization.jsonObject(with: data) as? [String: String]
    #expect(json?["message"] == "Hello, world!")
  }

  @Test("invoke with custom method")
  func testInvokeWithCustomMethod() async throws {
    Mock(
      url: baseURL.appendingPathComponent("hello"),
      statusCode: 200,
      data: [.get: Data()]
    ).register()

    let client = makeClient()

    let (_, response) = try await client.invoke("hello") { options in
      options.method = "GET"
    }

    #expect(response.statusCode == 200)
  }

  @Test("invoke with query parameters")
  func testInvokeWithQueryParameters() async throws {
    Mock(
      url: baseURL.appendingPathComponent("hello"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: Data()]
    ).register()

    let client = makeClient()

    let (_, response) = try await client.invoke("hello") { options in
      options.query = ["key": "value", "foo": "bar"]
    }

    #expect(response.statusCode == 200)
  }

  @Test("invoke with request body")
  func testInvokeWithBody() async throws {
    let expectedBody = Data("{\"name\":\"Supabase\"}".utf8)

    Mock(
      url: baseURL.appendingPathComponent("hello"),
      statusCode: 200,
      data: [.post: Data()]
    ).register()

    let client = makeClient()

    let (_, response) = try await client.invoke("hello") { options in
      options.body = expectedBody
    }

    #expect(response.statusCode == 200)
  }

  // MARK: - Typed Response Tests

  @Test("invoke with type decoding")
  func testInvokeWithTypeDecoding() async throws {
    struct Response: Decodable, Equatable {
      let message: String
      let status: String
    }

    let responseData = Data(
      "{\"message\":\"Hello, world!\",\"status\":\"ok\"}".utf8
    )

    Mock(
      url: baseURL.appendingPathComponent("hello"),
      statusCode: 200,
      data: [.post: responseData]
    ).register()

    let client = makeClient()
    let (result, response) = try await client.invoke(
      "hello",
      as: Response.self
    )

    #expect(response.statusCode == 200)
    #expect(result.message == "Hello, world!")
    #expect(result.status == "ok")
  }

  @Test("invoke with custom decoder")
  func testInvokeWithCustomDecoder() async throws {
    struct Response: Decodable {
      let createdAt: Date
    }

    let responseData = Data("{\"createdAt\":\"2025-01-01T00:00:00Z\"}".utf8)

    Mock(
      url: baseURL.appendingPathComponent("hello"),
      statusCode: 200,
      data: [.post: responseData]
    ).register()

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let client = makeClient()
    let (result, _) = try await client.invoke(
      "hello",
      as: Response.self,
      decoder: decoder
    )

    #expect(result.createdAt.timeIntervalSince1970 > 0)
  }

  // MARK: - Streaming Tests

  @Test("streamInvoke returns async bytes")
  func testStreamInvoke() async throws {
    let expectedData = Data("Hello, streaming world!".utf8)

    Mock(
      url: baseURL.appendingPathComponent("stream"),
      statusCode: 200,
      data: [.post: expectedData]
    ).register()

    let client = makeClient()
    let (bytes, response) = try await client.streamInvoke("stream")

    #expect(response.statusCode == 200)

    var collectedData = Data()
    for try await byte in bytes {
      collectedData.append(byte)
    }

    #expect(collectedData == expectedData)
  }

  @Test("streamInvoke with custom options")
  func testStreamInvokeWithOptions() async throws {
    Mock(
      url: baseURL.appendingPathComponent("stream"),
      statusCode: 200,
      data: [.get: Data("stream".utf8)]
    ).register()

    let client = makeClient()

    let (_, response) = try await client.streamInvoke("stream") { options in
      options.method = "GET"
      options.headers = ["X-Stream-Header": "stream-value"]
    }

    #expect(response.statusCode == 200)
  }

  // MARK: - Error Handling Tests

  @Test("invoke throws FunctionsError on non-2xx status code")
  func testInvokeThrowsOnNon2xxStatus() async throws {
    Mock(
      url: baseURL.appendingPathComponent("missing"),
      statusCode: 404,
      data: [.post: Data("{\"error\":\"Function not found\"}".utf8)]
    ).register()

    let client = makeClient()

    await #expect(throws: FunctionsClientV2.FunctionsError.self) {
      try await client.invoke("missing")
    }
  }

  @Test("invoke throws FunctionsError on relay error")
  func testInvokeThrowsOnRelayError() async throws {
    Mock(
      url: baseURL.appendingPathComponent("hello"),
      statusCode: 200,
      data: [.post: Data("Relay error occurred".utf8)],
      additionalHeaders: ["X-Relay-Error": "true"]
    ).register()

    let client = makeClient()

    await #expect(throws: FunctionsClientV2.FunctionsError.self) {
      try await client.invoke("hello")
    }
  }

  @Test("invoke throws FunctionsError with descriptive message")
  func testInvokeErrorMessage() async throws {
    Mock(
      url: baseURL.appendingPathComponent("failing-function"),
      statusCode: 500,
      data: [.post: Data("Internal server error".utf8)]
    ).register()

    let client = makeClient()

    do {
      _ = try await client.invoke("failing-function")
      Issue.record("Expected FunctionsError to be thrown")
    } catch let error as FunctionsClientV2.FunctionsError {
      #expect(error.message.contains("failing-function"))
      #expect(error.message.contains("500"))
    }
  }

  @Test("streamInvoke throws FunctionsError on error status")
  func testStreamInvokeThrowsOnErrorStatus() async throws {
    Mock(
      url: baseURL.appendingPathComponent("forbidden"),
      statusCode: 403,
      data: [.post: Data("Forbidden".utf8)]
    ).register()

    let client = makeClient()

    await #expect(throws: FunctionsClientV2.FunctionsError.self) {
      _ = try await client.streamInvoke("forbidden")
    }
  }

  @Test("typed invoke throws DecodingError on invalid JSON")
  func testTypedInvokeThrowsDecodingError() async throws {
    struct Response: Decodable {
      let message: String
    }

    Mock(
      url: baseURL.appendingPathComponent("hello"),
      statusCode: 200,
      data: [.post: Data("{\"unexpected\":\"field\"}".utf8)]
    ).register()

    let client = makeClient()

    await #expect(throws: DecodingError.self) {
      _ = try await client.invoke("hello", as: Response.self)
    }
  }

  // MARK: - Request Adapter Tests

  @Test("RequestAdapter modifies outgoing requests")
  func testRequestAdapter() async throws {
    let adapted = LockIsolated(false)

    Mock(
      url: baseURL.appendingPathComponent("hello"),
      statusCode: 200,
      data: [.post: Data()]
    ).register()

    let adapter = MockRequestAdapter { request in
      adapted.setValue(true)
      var adaptedRequest = request
      adaptedRequest.setValue("true", forHTTPHeaderField: "X-Adapted")
      return adaptedRequest
    }

    let config = URLSessionConfiguration.default
    config.protocolClasses = [MockingURLProtocol.self]

    let client = FunctionsClientV2(
      baseURL: baseURL,
      sessionConfiguration: config,
      requestAdapter: adapter,
      headers: ["apikey": apiKey]
    )

    _ = try await client.invoke("hello")

    #expect(adapted.value == true)
  }

  @Test("Multiple RequestAdapters chain correctly")
  func testMultipleRequestAdapters() async throws {
    let firstCalled = LockIsolated(false)
    let secondCalled = LockIsolated(false)

    Mock(
      url: baseURL.appendingPathComponent("hello"),
      statusCode: 200,
      data: [.post: Data()]
    ).register()

    let adapter1 = MockRequestAdapter { request in
      firstCalled.setValue(true)
      var adaptedRequest = request
      adaptedRequest.setValue("1", forHTTPHeaderField: "X-First")
      return adaptedRequest
    }

    let adapter2 = MockRequestAdapter { request in
      secondCalled.setValue(true)
      var adaptedRequest = request
      adaptedRequest.setValue("2", forHTTPHeaderField: "X-Second")
      return adaptedRequest
    }

    let compositeAdapter = Adapters([adapter1, adapter2])

    let config = URLSessionConfiguration.default
    config.protocolClasses = [MockingURLProtocol.self]

    let client = FunctionsClientV2(
      baseURL: baseURL,
      sessionConfiguration: config,
      requestAdapter: compositeAdapter,
      headers: ["apikey": apiKey]
    )

    _ = try await client.invoke("hello")

    #expect(firstCalled.value == true)
    #expect(secondCalled.value == true)
  }

  // MARK: - Response Interceptor Tests

  @Test("ResponseInterceptor can inspect responses")
  func testResponseInterceptor() async throws {
    let interceptorCalled = LockIsolated(false)

    Mock(
      url: baseURL.appendingPathComponent("hello"),
      statusCode: 200,
      data: [.post: Data("test".utf8)],
      additionalHeaders: ["X-Custom": "value"]
    ).register()

    let interceptor = MockResponseInterceptor { body, response in
      interceptorCalled.setValue(true)
      return (body, response)
    }

    let config = URLSessionConfiguration.default
    config.protocolClasses = [MockingURLProtocol.self]

    let client = FunctionsClientV2(
      baseURL: baseURL,
      sessionConfiguration: config,
      responseInterceptor: interceptor,
      headers: ["apikey": apiKey]
    )

    _ = try await client.invoke("hello")

    #expect(interceptorCalled.value == true)
  }

  @Test("ResponseInterceptor can modify response data")
  func testResponseInterceptorModifiesData() async throws {
    Mock(
      url: baseURL.appendingPathComponent("hello"),
      statusCode: 200,
      data: [.post: Data("original".utf8)]
    ).register()

    let interceptor = MockResponseInterceptor { body, response in
      let modifiedData = Data("modified".utf8)
      return (.data(modifiedData), response)
    }

    let config = URLSessionConfiguration.default
    config.protocolClasses = [MockingURLProtocol.self]

    let client = FunctionsClientV2(
      baseURL: baseURL,
      sessionConfiguration: config,
      responseInterceptor: interceptor,
      headers: ["apikey": apiKey]
    )

    let (data, _) = try await client.invoke("hello")
    let string = String(data: data, encoding: .utf8)

    #expect(string == "modified")
  }

  @Test("Multiple ResponseInterceptors chain correctly")
  func testMultipleResponseInterceptors() async throws {
    let firstCalled = LockIsolated(false)
    let secondCalled = LockIsolated(false)

    Mock(
      url: baseURL.appendingPathComponent("hello"),
      statusCode: 200,
      data: [.post: Data()]
    ).register()

    let interceptor1 = MockResponseInterceptor { body, response in
      firstCalled.setValue(true)
      return (body, response)
    }

    let interceptor2 = MockResponseInterceptor { body, response in
      secondCalled.setValue(true)
      return (body, response)
    }

    let compositeInterceptor = Interceptors([interceptor1, interceptor2])

    let config = URLSessionConfiguration.default
    config.protocolClasses = [MockingURLProtocol.self]

    let client = FunctionsClientV2(
      baseURL: baseURL,
      sessionConfiguration: config,
      responseInterceptor: compositeInterceptor,
      headers: ["apikey": apiKey]
    )

    _ = try await client.invoke("hello")

    #expect(firstCalled.value == true)
    #expect(secondCalled.value == true)
  }

  // MARK: - FunctionsError Tests

  @Test("FunctionsError conforms to LocalizedError")
  func testFunctionsErrorLocalizedError() {
    let error = FunctionsClientV2.FunctionsError("Test error message")

    #expect(error.localizedDescription == "Test error message")
    #expect(error.errorDescription == "Test error message")
  }

  // MARK: - Concurrency Tests

  @Test("Multiple concurrent invocations work correctly")
  func testConcurrentInvocations() async throws {
    // Register mocks for all function calls
    for i in 0..<5 {
      Mock(
        url: baseURL.appendingPathComponent("function-\(i)"),
        statusCode: 200,
        data: [.post: Data("{\"function\":\"function-\(i)\"}".utf8)]
      ).register()
    }

    let client = makeClient()

    // Launch multiple concurrent invocations
    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<5 {
        group.addTask {
          let (data, response) = try await client.invoke(
            "function-\(i)"
          )
          #expect(response.statusCode == 200)
          #expect(data.count > 0)
        }
      }

      try await group.waitForAll()
    }
  }

  @Test("Actor isolation prevents data races")
  func testActorIsolation() async throws {
    let client = FunctionsClientV2(
      baseURL: baseURL,
      headers: ["apikey": apiKey]
    )

    // These operations should be serialized by the actor
    await client.setAuth("token-1")
    let headers1 = await client.headers["Authorization"]

    await client.setAuth("token-2")
    let headers2 = await client.headers["Authorization"]

    #expect(headers1 == "Bearer token-1")
    #expect(headers2 == "Bearer token-2")
  }
}
