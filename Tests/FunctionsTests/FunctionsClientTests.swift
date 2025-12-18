import ConcurrencyExtras
import Foundation
import HTTPClient
import HTTPTypes
import Helpers
import Mocker
import Testing

@testable import Functions

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite(.serialized)
struct FunctionsClientTests {
  private let baseURL = URL(string: "https://example.supabase.co/functions/v1")!

  private func makeClient(
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    logger: (any SupabaseLogger)? = nil
  ) -> FunctionsClient {
    FunctionsClient(
      url: baseURL,
      headers: headers,
      region: region,
      session: .init(configuration: .mocking()),
      logger: logger
    )
  }

  private func makeURL(functionName: String) -> URL {
    baseURL.appendingPathComponent(functionName)
  }

  private func requestBody(_ request: URLRequest) -> Data? {
    request.httpBody ?? request.httpBodyStream.map(readAllBytes(from:))
  }

  private func readAllBytes(from stream: InputStream) -> Data {
    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 16 * 1024)
    while stream.hasBytesAvailable {
      let read = stream.read(&buffer, maxLength: buffer.count)
      if read > 0 {
        data.append(buffer, count: read)
      } else {
        break
      }
    }
    return data
  }

  @Test
  func requestIdleTimeout_is150Seconds() {
    #expect(FunctionsClient.requestIdleTimeout == 150)
  }

  @Test
  func init_setsDefaultXClientInfoHeaderIfMissing() async throws {
    defer { Mocker.removeAll() }

    let functionName = "hello-\(UUID().uuidString)"
    let url = makeURL(functionName: functionName)

    let capturedRequest = LockIsolated<URLRequest?>(nil)

    var mock = Mock(url: url, ignoreQuery: true, statusCode: 200, data: [.post: Data()])
    mock.onRequestHandler = OnRequestHandler(requestCallback: { request in
      capturedRequest.withValue { $0 = request }
    })
    mock.register()

    let client = makeClient(headers: ["X-Foo": "bar"])
    _ = try await client.invoke(functionName) { _ in }

    let request = capturedRequest.value

    #expect(request?.value(forHTTPHeaderField: "X-Foo") == "bar")

    let xClientInfo = request?.value(forHTTPHeaderField: "X-Client-Info")
    #expect(xClientInfo?.hasPrefix("functions-swift/") == true)
  }

  @Test
  func init_doesNotOverrideProvidedXClientInfoHeader() async throws {
    defer { Mocker.removeAll() }

    let functionName = "hello-\(UUID().uuidString)"
    let url = makeURL(functionName: functionName)

    let capturedRequest = LockIsolated<URLRequest?>(nil)

    var mock = Mock(url: url, ignoreQuery: true, statusCode: 200, data: [.post: Data()])
    mock.onRequestHandler = OnRequestHandler(requestCallback: { request in
      capturedRequest.withValue { $0 = request }
    })
    mock.register()

    let client = makeClient(headers: ["X-Client-Info": "my-client/1.0"])
    _ = try await client.invoke(functionName) { _ in }

    let request = capturedRequest.value

    #expect(request?.value(forHTTPHeaderField: "X-Client-Info") == "my-client/1.0")
  }

  @Test
  func setAuth_setsAndClearsAuthorizationHeader() async throws {
    defer { Mocker.removeAll() }

    let functionName = "hello-\(UUID().uuidString)"
    let url = makeURL(functionName: functionName)

    let captured = LockIsolated<[URLRequest]>([])

    var mock = Mock(url: url, ignoreQuery: true, statusCode: 200, data: [.post: Data()])
    mock.onRequestHandler = OnRequestHandler(requestCallback: { request in
      captured.withValue { $0.append(request) }
    })
    mock.register()

    let client = makeClient()
    client.setAuth(token: "jwt-token")
    _ = try await client.invoke(functionName) { _ in }

    client.setAuth(token: nil)
    _ = try await client.invoke(functionName) { _ in }

    let requests = captured.value

    #expect(requests.count == 2)
    #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer jwt-token")
    #expect(requests.last?.value(forHTTPHeaderField: "Authorization") == nil)
  }

  @Test
  func invoke_buildsCorrectURLMethodHeadersQuery() async throws {
    defer { Mocker.removeAll() }

    let functionName = "hello-\(UUID().uuidString)"
    let url = makeURL(functionName: functionName)

    let capturedRequest = LockIsolated<URLRequest?>(nil)

    var mock = Mock(url: url, ignoreQuery: true, statusCode: 200, data: [.get: Data("ok".utf8)])
    mock.onRequestHandler = OnRequestHandler(requestCallback: { request in
      capturedRequest.withValue { $0 = request }
    })
    mock.register()

    let client = makeClient(headers: ["X-Default": "1", "X-Shared": "init"])

    _ = try await client.invoke(functionName) { options in
      options.method = .get
      options.headers[HTTPField.Name("X-Shared")!] = "invoke"
      options.headers[HTTPField.Name("X-Invoke")!] = "2"
      options.query = [
        .init(name: "foo", value: "bar"),
        .init(name: "baz", value: "qux"),
      ]
    }

    let request = capturedRequest.value

    #expect(request?.httpMethod == "GET")
    #expect(request?.value(forHTTPHeaderField: "X-Default") == "1")
    #expect(request?.value(forHTTPHeaderField: "X-Shared") == "invoke")
    #expect(request?.value(forHTTPHeaderField: "X-Invoke") == "2")

    let requestURL = try #require(request?.url)
    let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
    #expect(components.path.hasSuffix("/functions/v1/\(functionName)"))
    let query = Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    #expect(query["foo"] == "bar")
    #expect(query["baz"] == "qux")
  }

  @Test
  func invoke_withRegion_addsHeaderAndForceFunctionRegionQueryItem_andUpdatesExisting() async throws
  {
    defer { Mocker.removeAll() }

    let functionName = "hello-\(UUID().uuidString)"
    let url = makeURL(functionName: functionName)

    let capturedRequest = LockIsolated<URLRequest?>(nil)

    var mock = Mock(url: url, ignoreQuery: true, statusCode: 200, data: [.post: Data()])
    mock.onRequestHandler = OnRequestHandler(requestCallback: { request in
      capturedRequest.withValue { $0 = request }
    })
    mock.register()

    let client = makeClient()
    _ = try await client.invoke(functionName) { options in
      options.region = .usEast1
      options.query = [
        .init(name: "forceFunctionRegion", value: "should-be-overwritten"),
        .init(name: "foo", value: "bar"),
      ]
    }

    let request = capturedRequest.value

    #expect(request?.value(forHTTPHeaderField: "x-region") == "us-east-1")

    let requestURL = try #require(request?.url)
    let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
    let query = Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    #expect(query["foo"] == "bar")
    #expect(query["forceFunctionRegion"] == "us-east-1")
  }

  @Test
  func invoke_usesDefaultClientRegionWhenOptionsRegionIsNil() async throws {
    defer { Mocker.removeAll() }

    let functionName = "hello-\(UUID().uuidString)"
    let url = makeURL(functionName: functionName)

    let capturedRequest = LockIsolated<URLRequest?>(nil)

    var mock = Mock(url: url, ignoreQuery: true, statusCode: 200, data: [.post: Data()])
    mock.onRequestHandler = OnRequestHandler(requestCallback: { request in
      capturedRequest.withValue { $0 = request }
    })
    mock.register()

    let client = makeClient(region: .euWest1)
    _ = try await client.invoke(functionName) { _ in }

    let request = capturedRequest.value

    #expect(request?.value(forHTTPHeaderField: "x-region") == "eu-west-1")

    let requestURL = try #require(request?.url)
    let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
    let query = Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    #expect(query["forceFunctionRegion"] == "eu-west-1")
  }

  @Test
  func invoke_withStringBody_setsContentType_andSendsBody() async throws {
    defer { Mocker.removeAll() }

    let functionName = "hello-\(UUID().uuidString)"
    let url = makeURL(functionName: functionName)

    let capturedRequest = LockIsolated<URLRequest?>(nil)

    var mock = Mock(url: url, ignoreQuery: true, statusCode: 200, data: [.post: Data()])
    mock.onRequestHandler = OnRequestHandler(requestCallback: { request in
      capturedRequest.withValue { $0 = request }
    })
    mock.register()

    let client = makeClient()
    _ = try await client.invoke(functionName) { options in
      options.body(string: "hello")
    }

    let request = capturedRequest.value

    #expect(request?.value(forHTTPHeaderField: "Content-Type") == "text/plain")

    let body = try #require(request.flatMap(requestBody(_:)))
    #expect(String(decoding: body, as: UTF8.self) == "hello")
  }

  @Test
  func invoke_non2xx_throwsHttpErrorWithResponseBody() async throws {
    defer { Mocker.removeAll() }

    let functionName = "hello-\(UUID().uuidString)"
    let url = makeURL(functionName: functionName)

    Mock(url: url, ignoreQuery: true, statusCode: 418, data: [.post: Data("nope".utf8)]).register()

    let client = makeClient()

    do {
      _ = try await client.invoke(functionName) { _ in }
      Issue.record("Expected FunctionsError.httpError")
    } catch let error as FunctionsError {
      switch error {
      case .httpError(let code, let data):
        #expect(code == 418)
        #expect(String(decoding: data, as: UTF8.self) == "nope")
      case .relayError:
        Issue.record("Expected httpError, got relayError")
      }
    }
  }

  @Test
  func invoke_successfulResponseWithRelayErrorHeader_throwsRelayError() async throws {
    defer { Mocker.removeAll() }

    let functionName = "hello-\(UUID().uuidString)"
    let url = makeURL(functionName: functionName)

    Mock(
      url: url,
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: Data()],
      additionalHeaders: ["x-relay-error": "true"]
    ).register()

    let client = makeClient()

    do {
      _ = try await client.invoke(functionName) { _ in }
      Issue.record("Expected FunctionsError.relayError")
    } catch let error as FunctionsError {
      switch error {
      case .relayError:
        break
      case .httpError:
        Issue.record("Expected relayError, got httpError")
      }
    }
  }

  @Test
  func invokeDecodable_decodesJSONResponse() async throws {
    defer { Mocker.removeAll() }

    let functionName = "hello-\(UUID().uuidString)"
    let url = makeURL(functionName: functionName)

    Mock(url: url, ignoreQuery: true, statusCode: 200, data: [.get: Data(#"{"name":"Ada"}"#.utf8)])
      .register()

    struct Person: Decodable, Equatable { let name: String }

    let client = makeClient()
    let person = try await client.invokeDecodable(functionName, as: Person.self) { options in
      options.method = .get
    }

    #expect(person == Person(name: "Ada"))
  }

  @Test
  func invoke_withMultipartFormData_usesMultipartBranchAndSetsContentType() async throws {
    defer { Mocker.removeAll() }

    let functionName = "upload-\(UUID().uuidString)"
    let url = makeURL(functionName: functionName)

    let capturedRequest = LockIsolated<URLRequest?>(nil)

    var mock = Mock(url: url, ignoreQuery: true, statusCode: 200, data: [.post: Data()])
    mock.onRequestHandler = OnRequestHandler(requestCallback: { request in
      capturedRequest.withValue { $0 = request }
    })
    mock.register()

    let client = makeClient()
    _ = try await client.invoke(functionName) { options in
      let form = MultipartFormData(boundary: "test-boundary")
      form.append(Data("hello".utf8), withName: "file", fileName: "a.txt", mimeType: "text/plain")
      options.body(multipartFormData: form)
    }

    let request = capturedRequest.value

    let contentType = request?.value(forHTTPHeaderField: "Content-Type")
    #expect(contentType?.contains("multipart/form-data") == true)
    #expect(contentType?.contains("boundary=test-boundary") == true)
  }

  @Test
  func loggerMiddleware_emitsVerboseLogs() async throws {
    defer { Mocker.removeAll() }

    let functionName = "hello-\(UUID().uuidString)"
    let url = makeURL(functionName: functionName)

    Mock(url: url, ignoreQuery: true, statusCode: 204, data: [.get: Data()]).register()

    let logger = CapturingLogger()
    let client = makeClient(logger: logger)

    _ = try await client.invoke(functionName) { options in
      options.method = .get
    }

    let messages = logger.messages
    #expect(messages.contains(where: { $0.contains("⬆️") }))
    #expect(messages.contains(where: { $0.contains("⬇️") }))
  }
}

extension URLSessionConfiguration {
  fileprivate static func mocking() -> URLSessionConfiguration {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockingURLProtocol.self]
    return config
  }
}

private final class CapturingLogger: SupabaseLogger, @unchecked Sendable {
  private let lock = NSLock()
  private var _messages: [String] = []

  var messages: [String] {
    lock.lock()
    defer { lock.unlock() }
    return _messages
  }

  func log(message: SupabaseLogMessage) {
    lock.lock()
    _messages.append(message.message)
    lock.unlock()
  }
}
