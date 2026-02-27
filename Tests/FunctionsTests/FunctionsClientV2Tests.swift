#if swift(>=6.0)
  import Foundation
  import Testing

  @testable import Functions

  #if canImport(FoundationNetworking)
    import FoundationNetworking
  #endif

  // MARK: - Test Helpers

  /// A mock URLProtocol that captures requests and returns configured responses.
  @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
  final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static var requestHandler:
      (
        @Sendable (URLRequest) async throws -> (
          HTTPURLResponse, Data?
        )
      )?

    override class func canInit(with request: URLRequest) -> Bool {
      true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
      request
    }

    override func startLoading() {
      guard let handler = Self.requestHandler else {
        fatalError("MockURLProtocol requestHandler not set")
      }

      Task {
        do {
          let (response, data) = try await handler(request)
          client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
          if let data {
            client?.urlProtocol(self, didLoad: data)
          }
          client?.urlProtocolDidFinishLoading(self)
        } catch {
          client?.urlProtocol(self, didFailWithError: error)
        }
      }
    }

    override func stopLoading() {}
  }

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

    func intercept(body: ResponseBody, response: HTTPURLResponse) async throws -> (
      ResponseBody, HTTPURLResponse
    ) {
      try await transform(body, response)
    }
  }

  // MARK: - Tests

  @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
  @Suite("FunctionsClientV2 Tests")
  struct FunctionsClientV2Tests {
    let baseURL = URL(string: "http://localhost:54321/functions/v1")!
    let apiKey =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"

    func makeSessionConfiguration() -> URLSessionConfiguration {
      let config = URLSessionConfiguration.ephemeral
      config.protocolClasses = [MockURLProtocol.self]
      return config
    }

    // MARK: - Initialization Tests

    @Test("Client initialization with URL and headers")
    func testInitialization() async {
      let client = FunctionsClientV2(
        url: baseURL,
        headers: ["apikey": apiKey, "Custom-Header": "value"]
      )

      #expect(await client.url == baseURL)
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

      #expect(await client.url == baseURL)
    }

    @Test("Client initialization with custom session configuration")
    func testInitializationWithCustomConfiguration() async {
      let config = URLSessionConfiguration.ephemeral
      let client = FunctionsClientV2(
        baseURL: baseURL,
        sessionConfiguration: config,
        headers: ["apikey": apiKey]
      )

      #expect(await client.url == baseURL)
    }

    // MARK: - Authentication Tests

    @Test("setAuth adds Authorization header")
    func testSetAuth() async {
      let client = FunctionsClientV2(url: baseURL, headers: ["apikey": apiKey])

      await client.setAuth("test-token")
      #expect(await client.headers["Authorization"] == "Bearer test-token")
    }

    @Test("setAuth with nil removes Authorization header")
    func testSetAuthWithNil() async {
      let client = FunctionsClientV2(url: baseURL, headers: ["apikey": apiKey])

      await client.setAuth("test-token")
      #expect(await client.headers["Authorization"] == "Bearer test-token")

      await client.setAuth(nil)
      #expect(await client.headers["Authorization"] == nil)
    }

    // MARK: - Basic Invocation Tests

    @Test("invoke returns raw data and response")
    func testInvokeRawData() async throws {
      MockURLProtocol.requestHandler = { request in
        #expect(request.url?.lastPathComponent == "hello")
        #expect(request.httpMethod == "POST")

        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
        let data = Data("{\"message\":\"Hello, world!\"}".utf8)
        return (response, data)
      }

      let client = FunctionsClientV2(
        baseURL: baseURL,
        sessionConfiguration: makeSessionConfiguration(),
        headers: ["apikey": apiKey]
      )

      let (data, response) = try await client.invoke("hello")

      #expect(response.statusCode == 200)
      #expect(data.count > 0)

      let json = try JSONSerialization.jsonObject(with: data) as? [String: String]
      #expect(json?["message"] == "Hello, world!")
    }

    @Test("invoke with custom method")
    func testInvokeWithCustomMethod() async throws {
      MockURLProtocol.requestHandler = { request in
        #expect(request.httpMethod == "GET")

        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
        return (response, Data())
      }

      let client = FunctionsClientV2(
        baseURL: baseURL,
        sessionConfiguration: makeSessionConfiguration(),
        headers: ["apikey": apiKey]
      )

      let (_, response) = try await client.invoke("hello") { options in
        options.method = "GET"
      }

      #expect(response.statusCode == 200)
    }

    @Test("invoke with custom headers")
    func testInvokeWithCustomHeaders() async throws {
      MockURLProtocol.requestHandler = { request in
        #expect(request.value(forHTTPHeaderField: "X-Custom-Header") == "custom-value")
        #expect(request.value(forHTTPHeaderField: "apikey") != nil)

        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
        return (response, Data())
      }

      let client = FunctionsClientV2(
        baseURL: baseURL,
        sessionConfiguration: makeSessionConfiguration(),
        headers: ["apikey": apiKey]
      )

      _ = try await client.invoke("hello") { options in
        options.headers = ["X-Custom-Header": "custom-value"]
      }
    }

    @Test("invoke with query parameters")
    func testInvokeWithQueryParameters() async throws {
      MockURLProtocol.requestHandler = { request in
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems

        #expect(queryItems?.contains(where: { $0.name == "key" && $0.value == "value" }) == true)

        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
        return (response, Data())
      }

      let client = FunctionsClientV2(
        baseURL: baseURL,
        sessionConfiguration: makeSessionConfiguration(),
        headers: ["apikey": apiKey]
      )

      _ = try await client.invoke("hello") { options in
        options.query = ["key": "value"]
      }
    }

    @Test("invoke with request body")
    func testInvokeWithBody() async throws {
      let expectedBody = Data("{\"name\":\"Supabase\"}".utf8)

      MockURLProtocol.requestHandler = { request in
        #expect(request.httpBody == expectedBody)
        #expect(
          request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
        return (response, Data())
      }

      let client = FunctionsClientV2(
        baseURL: baseURL,
        sessionConfiguration: makeSessionConfiguration(),
        headers: ["apikey": apiKey]
      )

      _ = try await client.invoke("hello") { options in
        options.body = expectedBody
      }
    }

    // MARK: - Typed Response Tests

    @Test("invoke with type decoding")
    func testInvokeWithTypeDecoding() async throws {
      struct Response: Decodable, Equatable {
        let message: String
        let status: String
      }

      MockURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
        let data = Data("{\"message\":\"Hello, world!\",\"status\":\"ok\"}".utf8)
        return (response, data)
      }

      let client = FunctionsClientV2(
        baseURL: baseURL,
        sessionConfiguration: makeSessionConfiguration(),
        headers: ["apikey": apiKey]
      )

      let (result, response) = try await client.invoke("hello", as: Response.self)

      #expect(response.statusCode == 200)
      #expect(result.message == "Hello, world!")
      #expect(result.status == "ok")
    }

    @Test("invoke with custom decoder")
    func testInvokeWithCustomDecoder() async throws {
      struct Response: Decodable, Equatable {
        let createdAt: Date
      }

      MockURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
        let data = Data("{\"createdAt\":\"2025-01-01T00:00:00Z\"}".utf8)
        return (response, data)
      }

      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601

      let client = FunctionsClientV2(
        baseURL: baseURL,
        sessionConfiguration: makeSessionConfiguration(),
        headers: ["apikey": apiKey]
      )

      let (result, _) = try await client.invoke("hello", as: Response.self, decoder: decoder)

      #expect(result.createdAt.timeIntervalSince1970 > 0)
    }

    // MARK: - Streaming Tests

    @Test("streamInvoke returns async bytes")
    func testStreamInvoke() async throws {
      let expectedData = Data("Hello, streaming world!".utf8)

      MockURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
        return (response, expectedData)
      }

      let client = FunctionsClientV2(
        baseURL: baseURL,
        sessionConfiguration: makeSessionConfiguration(),
        headers: ["apikey": apiKey]
      )

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
      MockURLProtocol.requestHandler = { request in
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "X-Stream-Header") == "stream-value")

        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
        return (response, Data("stream".utf8))
      }

      let client = FunctionsClientV2(
        baseURL: baseURL,
        sessionConfiguration: makeSessionConfiguration(),
        headers: ["apikey": apiKey]
      )

      _ = try await client.streamInvoke("stream") { options in
        options.method = "GET"
        options.headers = ["X-Stream-Header": "stream-value"]
      }
    }

    // MARK: - Error Handling Tests

    @Test("invoke throws FunctionsError on non-2xx status code")
    func testInvokeThrowsOnNon2xxStatus() async throws {
      MockURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 404,
          httpVersion: nil,
          headerFields: nil
        )!
        let data = Data("{\"error\":\"Function not found\"}".utf8)
        return (response, data)
      }

      let client = FunctionsClientV2(
        baseURL: baseURL,
        sessionConfiguration: makeSessionConfiguration(),
        headers: ["apikey": apiKey]
      )

      await #expect(throws: FunctionsClientV2.FunctionsError.self) {
        try await client.invoke("missing")
      }
    }

    @Test("invoke throws FunctionsError on relay error")
    func testInvokeThrowsOnRelayError() async throws {
      MockURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: ["X-Relay-Error": "true"]
        )!
        let data = Data("Relay error occurred".utf8)
        return (response, data)
      }

      let client = FunctionsClientV2(
        baseURL: baseURL,
        sessionConfiguration: makeSessionConfiguration(),
        headers: ["apikey": apiKey]
      )

      await #expect(throws: FunctionsClientV2.FunctionsError.self) {
        try await client.invoke("hello")
      }
    }

    @Test("invoke throws FunctionsError with descriptive message")
    func testInvokeErrorMessage() async throws {
      MockURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 500,
          httpVersion: nil,
          headerFields: nil
        )!
        let data = Data("Internal server error".utf8)
        return (response, data)
      }

      let client = FunctionsClientV2(
        baseURL: baseURL,
        sessionConfiguration: makeSessionConfiguration(),
        headers: ["apikey": apiKey]
      )

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
      MockURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 403,
          httpVersion: nil,
          headerFields: nil
        )!
        return (response, Data("Forbidden".utf8))
      }

      let client = FunctionsClientV2(
        baseURL: baseURL,
        sessionConfiguration: makeSessionConfiguration(),
        headers: ["apikey": apiKey]
      )

      await #expect(throws: FunctionsClientV2.FunctionsError.self) {
        _ = try await client.streamInvoke("forbidden")
      }
    }

    @Test("typed invoke throws DecodingError on invalid JSON")
    func testTypedInvokeThrowsDecodingError() async throws {
      struct Response: Decodable {
        let message: String
      }

      MockURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
        // Invalid JSON for the expected structure
        let data = Data("{\"unexpected\":\"field\"}".utf8)
        return (response, data)
      }

      let client = FunctionsClientV2(
        baseURL: baseURL,
        sessionConfiguration: makeSessionConfiguration(),
        headers: ["apikey": apiKey]
      )

      await #expect(throws: DecodingError.self) {
        _ = try await client.invoke("hello", as: Response.self)
      }
    }

    // MARK: - Request Adapter Tests

    @Test("RequestAdapter modifies outgoing requests")
    func testRequestAdapter() async throws {
      MockURLProtocol.requestHandler = { request in
        // Verify the adapter added the header
        #expect(request.value(forHTTPHeaderField: "X-Adapted") == "true")

        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
        return (response, Data())
      }

      let adapter = MockRequestAdapter { request in
        var adaptedRequest = request
        adaptedRequest.setValue("true", forHTTPHeaderField: "X-Adapted")
        return adaptedRequest
      }

      let client = FunctionsClientV2(
        baseURL: baseURL,
        sessionConfiguration: makeSessionConfiguration(),
        requestAdapter: adapter,
        headers: ["apikey": apiKey]
      )

      _ = try await client.invoke("hello")
    }

    @Test("Multiple RequestAdapters chain correctly")
    func testMultipleRequestAdapters() async throws {
      MockURLProtocol.requestHandler = { request in
        #expect(request.value(forHTTPHeaderField: "X-First") == "1")
        #expect(request.value(forHTTPHeaderField: "X-Second") == "2")

        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
        return (response, Data())
      }

      let adapter1 = MockRequestAdapter { request in
        var adaptedRequest = request
        adaptedRequest.setValue("1", forHTTPHeaderField: "X-First")
        return adaptedRequest
      }

      let adapter2 = MockRequestAdapter { request in
        var adaptedRequest = request
        adaptedRequest.setValue("2", forHTTPHeaderField: "X-Second")
        return adaptedRequest
      }

      let compositeAdapter = Adapters([adapter1, adapter2])

      let client = FunctionsClientV2(
        baseURL: baseURL,
        sessionConfiguration: makeSessionConfiguration(),
        requestAdapter: compositeAdapter,
        headers: ["apikey": apiKey]
      )

      _ = try await client.invoke("hello")
    }

    // MARK: - Response Interceptor Tests

    @Test("ResponseInterceptor can inspect responses")
    func testResponseInterceptor() async throws {
      var interceptorCalled = false

      MockURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: ["X-Custom": "value"]
        )!
        return (response, Data("test".utf8))
      }

      let interceptor = MockResponseInterceptor { body, response in
        interceptorCalled = true
        #expect(response.value(forHTTPHeaderField: "X-Custom") == "value")
        return (body, response)
      }

      let client = FunctionsClientV2(
        baseURL: baseURL,
        sessionConfiguration: makeSessionConfiguration(),
        responseInterceptor: interceptor,
        headers: ["apikey": apiKey]
      )

      _ = try await client.invoke("hello")

      #expect(interceptorCalled)
    }

    @Test("ResponseInterceptor can modify response data")
    func testResponseInterceptorModifiesData() async throws {
      MockURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
        return (response, Data("original".utf8))
      }

      let interceptor = MockResponseInterceptor { body, response in
        // Transform the response data
        let modifiedData = Data("modified".utf8)
        return (.data(modifiedData), response)
      }

      let client = FunctionsClientV2(
        baseURL: baseURL,
        sessionConfiguration: makeSessionConfiguration(),
        responseInterceptor: interceptor,
        headers: ["apikey": apiKey]
      )

      let (data, _) = try await client.invoke("hello")
      let string = String(data: data, encoding: .utf8)

      #expect(string == "modified")
    }

    @Test("Multiple ResponseInterceptors chain correctly")
    func testMultipleResponseInterceptors() async throws {
      var firstCalled = false
      var secondCalled = false

      MockURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
        return (response, Data())
      }

      let interceptor1 = MockResponseInterceptor { body, response in
        firstCalled = true
        return (body, response)
      }

      let interceptor2 = MockResponseInterceptor { body, response in
        secondCalled = true
        #expect(firstCalled, "First interceptor should be called before second")
        return (body, response)
      }

      let compositeInterceptor = Interceptors([interceptor1, interceptor2])

      let client = FunctionsClientV2(
        baseURL: baseURL,
        sessionConfiguration: makeSessionConfiguration(),
        responseInterceptor: compositeInterceptor,
        headers: ["apikey": apiKey]
      )

      _ = try await client.invoke("hello")

      #expect(firstCalled)
      #expect(secondCalled)
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
      MockURLProtocol.requestHandler = { request in
        // Simulate some async work
        try await Task.sleep(for: .milliseconds(10))

        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
        let functionName = request.url?.lastPathComponent ?? "unknown"
        let data = Data("{\"function\":\"\(functionName)\"}".utf8)
        return (response, data)
      }

      let client = FunctionsClientV2(
        baseURL: baseURL,
        sessionConfiguration: makeSessionConfiguration(),
        headers: ["apikey": apiKey]
      )

      // Launch multiple concurrent invocations
      try await withThrowingTaskGroup(of: Void.self) { group in
        for i in 0..<5 {
          group.addTask {
            let (data, response) = try await client.invoke("function-\(i)")
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
#else
  import XCTest

  final class FunctionsClientV2Tests: XCTestCase {
    func testSwift6Required() {
      XCTFail(
        "FunctionsClientV2 tests require Swift 6.0+. Please upgrade to Xcode 16+ to run these tests."
      )
    }
  }
#endif
