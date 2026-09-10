//
//  LoggerInterceptorTests.swift
//  Supabase
//
//  Created by Coverage Tests
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import HTTPTypesFoundation
import Logging
import Testing

@testable import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct LoggerInterceptorTests {

  typealias Method = HTTPTypes.HTTPRequest.Method

  // MARK: - Mock Logger

  final class LogCapture: @unchecked Sendable {
    var verboseLogs: [String] = []
    var errorLogs: [String] = []
  }

  struct CapturingLogHandler: LogHandler {
    let capture: LogCapture
    var metadata: Logging.Logger.Metadata = [:]
    var logLevel: Logging.Logger.Level = .trace

    subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
      get { metadata[key] }
      set { metadata[key] = newValue }
    }

    func log(
      level: Logging.Logger.Level,
      message: Logging.Logger.Message,
      metadata: Logging.Logger.Metadata?,
      source: String,
      file: String,
      function: String,
      line: UInt
    ) {
      switch level {
      case .trace:
        capture.verboseLogs.append("\(message)")
      case .error:
        capture.errorLogs.append("\(message)")
      default:
        break
      }
    }
  }

  func makeLogger() -> (Logging.Logger, LogCapture) {
    let capture = LogCapture()
    var logger = Logging.Logger(label: "test") { _ in CapturingLogHandler(capture: capture) }
    logger.logLevel = .trace
    return (logger, capture)
  }

  // MARK: - Helper Methods

  func createTestRequest(
    url: String = "https://api.example.com/test",
    method: Method = .get
  ) -> HTTPTypes.HTTPRequest {
    HTTPTypes.HTTPRequest(method: method, url: URL(string: url)!)
  }

  func createTestResponse(statusCode: Int = 200) -> HTTPTypes.HTTPResponse {
    HTTPTypes.HTTPResponse(status: HTTPTypes.HTTPResponse.Status(code: statusCode))
  }

  // MARK: - Interceptor Tests

  @Test
  func interceptorLogsRequest() async throws {
    let (logger, capture) = makeLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    let request = createTestRequest(url: "https://api.example.com/users", method: .get)

    let _ = try await interceptor.intercept(request, body: nil) { _, _ in
      (self.createTestResponse(), nil)
    }

    // Verify request was logged
    #expect(capture.verboseLogs.count == 2)  // Request and response
    #expect(capture.verboseLogs[0].contains("Request:"))
    #expect(capture.verboseLogs[0].contains("/users"))
  }

  @Test
  func interceptorLogsResponse() async throws {
    let (logger, capture) = makeLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    let request = createTestRequest()
    let responseData = #"{"success": true}"#.data(using: .utf8)!

    let _ = try await interceptor.intercept(request, body: nil) { _, _ in
      (self.createTestResponse(statusCode: 200), HTTPBody(responseData))
    }

    // Verify response was logged
    #expect(capture.verboseLogs.count == 2)
    #expect(capture.verboseLogs[1].contains("Response: Status code: 200"))
  }

  @Test
  func interceptorLogsContentLengthHeaderWhenPresent() async throws {
    let (logger, capture) = makeLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    let _ = try await interceptor.intercept(createTestRequest(), body: nil) { _, _ in
      (
        HTTPTypes.HTTPResponse(status: .ok, headerFields: [.contentLength: "17"]),
        HTTPBody(#"{"success": true}"#.data(using: .utf8)!)
      )
    }

    #expect(capture.verboseLogs[1].contains("Content-Length: 17"))
  }

  @Test
  func interceptorLogsDashWhenContentLengthIsMissing() async throws {
    let (logger, capture) = makeLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    let _ = try await interceptor.intercept(createTestRequest(), body: nil) { _, _ in
      (self.createTestResponse(), nil)
    }

    #expect(capture.verboseLogs[1].contains("Content-Length: -"))
  }

  @Test
  func interceptorLogsError() async throws {
    let (logger, capture) = makeLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    let request = createTestRequest()

    struct TestError: Error {}

    do {
      let _ = try await interceptor.intercept(request, body: nil) { _, _ in
        throw TestError()
      }
      Issue.record("Should have thrown error")
    } catch {
      // Expected error
    }

    // Verify error was logged
    #expect(capture.errorLogs.count == 1)
    #expect(capture.errorLogs[0].contains("Response: Failure"))
  }

  @Test
  func interceptorWithJSONBody() async throws {
    let (logger, capture) = makeLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    let jsonBody = #"{"name": "test", "value": 123}"#.data(using: .utf8)!
    let request = createTestRequest(method: .post)

    let _ = try await interceptor.intercept(request, body: HTTPBody(jsonBody)) { _, _ in
      (self.createTestResponse(), nil)
    }

    // Verify JSON body was logged
    #expect(capture.verboseLogs[0].contains("Body:"))
    #expect(capture.verboseLogs[0].contains("name"))
  }

  @Test
  func interceptorWithEmptyBody() async throws {
    let (logger, capture) = makeLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    let request = createTestRequest(method: .get)

    let _ = try await interceptor.intercept(request, body: nil) { _, _ in
      (self.createTestResponse(), nil)
    }

    // Verify empty body handling
    #expect(capture.verboseLogs[0].contains("<none>"))
  }

  @Test
  func interceptorWithDifferentMethods() async throws {
    let methods: [(Method, String)] = [
      (.get, "GET"),
      (.post, "POST"),
      (.put, "PUT"),
      (.delete, "DELETE"),
      (.patch, "PATCH"),
    ]

    for (method, methodString) in methods {
      let (logger, capture) = makeLogger()
      let interceptor = LoggerInterceptor(logger: logger)

      let request = createTestRequest(method: method)

      let _ = try await interceptor.intercept(request, body: nil) { _, _ in
        (self.createTestResponse(), nil)
      }

      #expect(
        capture.verboseLogs[0].contains("Request: \(methodString)"),
        "Should log \(methodString) request"
      )
    }
  }

  @Test
  func interceptorWithDifferentStatusCodes() async throws {
    let statusCodes = [200, 201, 400, 401, 404, 500]

    for statusCode in statusCodes {
      let (logger, capture) = makeLogger()
      let interceptor = LoggerInterceptor(logger: logger)

      let request = createTestRequest()

      let _ = try await interceptor.intercept(request, body: nil) { _, _ in
        (self.createTestResponse(statusCode: statusCode), nil)
      }

      #expect(
        capture.verboseLogs[1].contains("Status code: \(statusCode)"),
        "Should log status code \(statusCode)"
      )
    }
  }

  // MARK: - Stringify Function Tests

  @Test
  func stringifyWithNilData() {
    let result = stringify(nil)
    #expect(result == "<none>")
  }

  @Test
  func stringifyWithJSONData() {
    let jsonData = #"{"key": "value", "number": 42}"#.data(using: .utf8)!
    let result = stringify(jsonData)

    #expect(result.contains("key"))
    #expect(result.contains("value"))
    #expect(result.contains("number"))
  }

  @Test
  func stringifyWithNonJSONData() {
    let textData = "Plain text content".data(using: .utf8)!
    let result = stringify(textData)

    #expect(result == "Plain text content")
  }

  @Test
  func stringifyWithInvalidUTF8Data() {
    // Invalid UTF-8 sequence
    let invalidData = Data([0xFF, 0xFE, 0xFD])
    let result = stringify(invalidData)

    #expect(result == "<failed>")
  }

  @Test
  func stringifyWithEmptyData() {
    let emptyData = Data()
    let result = stringify(emptyData)

    // Empty JSON object or empty string
    #expect(result.isEmpty)
  }

  @Test
  func stringifyWithComplexJSON() {
    let complexJSON = """
      {
        "users": [
          {"id": 1, "name": "Alice"},
          {"id": 2, "name": "Bob"}
        ],
        "total": 2,
        "nested": {
          "key": "value"
        }
      }
      """.data(using: .utf8)!

    let result = stringify(complexJSON)

    #expect(result.contains("users"))
    #expect(result.contains("Alice"))
    #expect(result.contains("nested"))
  }

  @Test
  func stringifyWithArrayJSON() {
    let arrayJSON = #"[1, 2, 3, 4, 5]"#.data(using: .utf8)!
    let result = stringify(arrayJSON)

    #expect(result.contains("1"))
    #expect(result.contains("5"))
  }

  @Test
  func stringifyWithBooleanJSON() {
    let boolJSON = #"{"active": true, "deleted": false}"#.data(using: .utf8)!
    let result = stringify(boolJSON)

    #expect(result.contains("active"))
    #expect(result.contains("true") || result.contains("1"))
  }

  @Test
  func stringifyWithNullJSON() {
    let nullJSON = #"{"value": null}"#.data(using: .utf8)!
    let result = stringify(nullJSON)

    #expect(result.contains("value"))
  }

  // MARK: - Integration Tests

  @Test
  func interceptorPassesThroughResponse() async throws {
    let (logger, _) = makeLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    let request = createTestRequest()
    let testData = "Test Response".data(using: .utf8)!

    let (head, body) = try await interceptor.intercept(request, body: nil) { _, _ in
      (self.createTestResponse(statusCode: 201), HTTPBody(testData))
    }

    // Verify response is passed through unchanged
    #expect(head.status.code == 201)
    #expect(try await Data(collecting: try #require(body), upTo: .max) == testData)
  }

  @Test
  func interceptorPassesThroughRequestBody() async throws {
    let (logger, _) = makeLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    let requestBody = #"{"name": "test"}"#.data(using: .utf8)!
    let seen = LockIsolated<Data?>(nil)

    let _ = try await interceptor.intercept(
      createTestRequest(method: .post), body: HTTPBody(requestBody)
    ) { _, body in
      let collected = try await Data(collecting: try #require(body), upTo: .max)
      seen.setValue(collected)
      return (self.createTestResponse(), nil)
    }

    #expect(seen.value == requestBody)
  }

  @Test
  func interceptorPassesThroughError() async throws {
    let (logger, _) = makeLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    struct CustomError: Error, Equatable {
      let message: String
    }

    let expectedError = CustomError(message: "Test error")

    do {
      let _ = try await interceptor.intercept(createTestRequest(), body: nil) { _, _ in
        throw expectedError
      }
      Issue.record("Should have thrown error")
    } catch let error as CustomError {
      #expect(error == expectedError)
    } catch {
      Issue.record("Wrong error type thrown")
    }
  }

  @Test
  func unknownLengthBodyPassesThroughUnconsumed() async throws {
    let (logger, _) = makeLogger()
    let sut = LoggerInterceptor(logger: logger)
    let body = HTTPBody(
      AsyncStream<ArraySlice<UInt8>> {
        $0.yield(ArraySlice([1, 2]))
        $0.finish()
      },
      length: .unknown, iterationBehavior: .single)

    let (_, returned) = try await sut.intercept(
      HTTPTypes.HTTPRequest(method: .get, url: URL(string: "https://example.com")!),
      body: nil
    ) { _, _ in (HTTPTypes.HTTPResponse(status: .ok), body) }

    #expect(returned === body)
    #expect(try await Data(collecting: try #require(returned), upTo: 10) == Data([1, 2]))
  }
}
