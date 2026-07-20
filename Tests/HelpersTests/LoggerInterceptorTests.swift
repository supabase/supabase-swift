//
//  LoggerInterceptorTests.swift
//  Supabase
//
//  Created by Coverage Tests
//

import Foundation
import HTTPTypes
import Testing

@testable import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct LoggerInterceptorTests {

  typealias Method = HTTPTypes.HTTPRequest.Method

  // MARK: - Mock Logger

  final class MockLogger: SupabaseLogger, @unchecked Sendable {
    var verboseLogs: [String] = []
    var errorLogs: [String] = []

    func log(message: SupabaseLogMessage) {
      switch message.level {
      case .verbose:
        verboseLogs.append(message.message)
      case .error:
        errorLogs.append(message.message)
      case .debug, .warning:
        break
      }
    }
  }

  // MARK: - Helper Methods

  func createTestRequest(
    url: String = "https://api.example.com/test",
    method: Method = .get,
    body: Data? = nil
  ) -> Helpers.HTTPRequest {
    Helpers.HTTPRequest(
      url: URL(string: url)!,
      method: method,
      body: body
    )
  }

  func createTestResponse(statusCode: Int = 200, data: Data = Data()) -> Helpers.HTTPResponse {
    let urlResponse = HTTPURLResponse(
      url: URL(string: "https://api.example.com/test")!,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: nil
    )!
    return Helpers.HTTPResponse(data: data, response: urlResponse)
  }

  // MARK: - Interceptor Tests

  @Test
  func interceptorLogsRequest() async throws {
    let logger = MockLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    let request = createTestRequest(url: "https://api.example.com/users", method: .get)
    let expectedResponse = createTestResponse()

    let _ = try await interceptor.intercept(request) { _ in
      return expectedResponse
    }

    // Verify request was logged
    #expect(logger.verboseLogs.count == 2)  // Request and response
    #expect(logger.verboseLogs[0].contains("Request:"))
    #expect(logger.verboseLogs[0].contains("/users"))
  }

  @Test
  func interceptorLogsResponse() async throws {
    let logger = MockLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    let request = createTestRequest()
    let responseData = #"{"success": true}"#.data(using: .utf8)!
    let expectedResponse = createTestResponse(statusCode: 200, data: responseData)

    let _ = try await interceptor.intercept(request) { _ in
      return expectedResponse
    }

    // Verify response was logged
    #expect(logger.verboseLogs.count == 2)
    #expect(logger.verboseLogs[1].contains("Response: Status code: 200"))
  }

  @Test
  func interceptorLogsError() async throws {
    let logger = MockLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    let request = createTestRequest()

    struct TestError: Error {}

    do {
      let _ = try await interceptor.intercept(request) { _ in
        throw TestError()
      }
      Issue.record("Should have thrown error")
    } catch {
      // Expected error
    }

    // Verify error was logged
    #expect(logger.errorLogs.count == 1)
    #expect(logger.errorLogs[0].contains("Response: Failure"))
  }

  @Test
  func interceptorWithJSONBody() async throws {
    let logger = MockLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    let jsonBody = #"{"name": "test", "value": 123}"#.data(using: .utf8)!
    let request = createTestRequest(method: .post, body: jsonBody)
    let expectedResponse = createTestResponse()

    let _ = try await interceptor.intercept(request) { _ in
      return expectedResponse
    }

    // Verify JSON body was logged
    #expect(logger.verboseLogs[0].contains("Body:"))
    #expect(logger.verboseLogs[0].contains("name"))
  }

  @Test
  func interceptorWithEmptyBody() async throws {
    let logger = MockLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    let request = createTestRequest(method: .get, body: Data?.none)
    let expectedResponse = createTestResponse()

    let _ = try await interceptor.intercept(request) { _ in
      return expectedResponse
    }

    // Verify empty body handling
    #expect(logger.verboseLogs[0].contains("<none>"))
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
      let logger = MockLogger()
      let interceptor = LoggerInterceptor(logger: logger)

      let request = createTestRequest(method: method)
      let expectedResponse = createTestResponse()

      let _ = try await interceptor.intercept(request) { _ in
        return expectedResponse
      }

      #expect(
        logger.verboseLogs[0].contains("Request:"),
        "Should log \(methodString) request"
      )
    }
  }

  @Test
  func interceptorWithDifferentStatusCodes() async throws {
    let statusCodes = [200, 201, 400, 401, 404, 500]

    for statusCode in statusCodes {
      let logger = MockLogger()
      let interceptor = LoggerInterceptor(logger: logger)

      let request = createTestRequest()
      let expectedResponse = createTestResponse(statusCode: statusCode)

      let _ = try await interceptor.intercept(request) { _ in
        return expectedResponse
      }

      #expect(
        logger.verboseLogs[1].contains("Status code: \(statusCode)"),
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
    let logger = MockLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    let request = createTestRequest()
    let testData = "Test Response".data(using: .utf8)!
    let expectedResponse = createTestResponse(statusCode: 201, data: testData)

    let actualResponse = try await interceptor.intercept(request) { _ in
      return expectedResponse
    }

    // Verify response is passed through unchanged
    #expect(actualResponse.statusCode == 201)
    #expect(actualResponse.data == testData)
  }

  @Test
  func interceptorPassesThroughError() async throws {
    let logger = MockLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    let request = createTestRequest()

    struct CustomError: Error, Equatable {
      let message: String
    }

    let expectedError = CustomError(message: "Test error")

    do {
      let _ = try await interceptor.intercept(request) { _ in
        throw expectedError
      }
      Issue.record("Should have thrown error")
    } catch let error as CustomError {
      #expect(error == expectedError)
    } catch {
      Issue.record("Wrong error type thrown")
    }
  }
}
