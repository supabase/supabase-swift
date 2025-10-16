//
//  LoggerInterceptorTests.swift
//  Supabase
//
//  Created by Coverage Tests
//

import XCTest
@testable import Helpers
import HTTPTypes

final class LoggerInterceptorTests: XCTestCase {

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

  func testInterceptorLogsRequest() async throws {
    let logger = MockLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    let request = createTestRequest(url: "https://api.example.com/users", method: .get)
    let expectedResponse = createTestResponse()

    let _ = try await interceptor.intercept(request) { _ in
      return expectedResponse
    }

    // Verify request was logged
    XCTAssertEqual(logger.verboseLogs.count, 2) // Request and response
    XCTAssertTrue(logger.verboseLogs[0].contains("Request:"))
    XCTAssertTrue(logger.verboseLogs[0].contains("/users"))
  }

  func testInterceptorLogsResponse() async throws {
    let logger = MockLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    let request = createTestRequest()
    let responseData = #"{"success": true}"#.data(using: .utf8)!
    let expectedResponse = createTestResponse(statusCode: 200, data: responseData)

    let _ = try await interceptor.intercept(request) { _ in
      return expectedResponse
    }

    // Verify response was logged
    XCTAssertEqual(logger.verboseLogs.count, 2)
    XCTAssertTrue(logger.verboseLogs[1].contains("Response: Status code: 200"))
  }

  func testInterceptorLogsError() async throws {
    let logger = MockLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    let request = createTestRequest()

    struct TestError: Error {}

    do {
      let _ = try await interceptor.intercept(request) { _ in
        throw TestError()
      }
      XCTFail("Should have thrown error")
    } catch {
      // Expected error
    }

    // Verify error was logged
    XCTAssertEqual(logger.errorLogs.count, 1)
    XCTAssertTrue(logger.errorLogs[0].contains("Response: Failure"))
  }

  func testInterceptorWithJSONBody() async throws {
    let logger = MockLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    let jsonBody = #"{"name": "test", "value": 123}"#.data(using: .utf8)!
    let request = createTestRequest(method: .post, body: jsonBody)
    let expectedResponse = createTestResponse()

    let _ = try await interceptor.intercept(request) { _ in
      return expectedResponse
    }

    // Verify JSON body was logged
    XCTAssertTrue(logger.verboseLogs[0].contains("Body:"))
    XCTAssertTrue(logger.verboseLogs[0].contains("name"))
  }

  func testInterceptorWithEmptyBody() async throws {
    let logger = MockLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    let request = createTestRequest(method: .get, body: Data?.none)
    let expectedResponse = createTestResponse()

    let _ = try await interceptor.intercept(request) { _ in
      return expectedResponse
    }

    // Verify empty body handling
    XCTAssertTrue(logger.verboseLogs[0].contains("<none>"))
  }

  func testInterceptorWithDifferentMethods() async throws {
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

      XCTAssertTrue(
        logger.verboseLogs[0].contains("Request:"),
        "Should log \(methodString) request"
      )
    }
  }

  func testInterceptorWithDifferentStatusCodes() async throws {
    let statusCodes = [200, 201, 400, 401, 404, 500]

    for statusCode in statusCodes {
      let logger = MockLogger()
      let interceptor = LoggerInterceptor(logger: logger)

      let request = createTestRequest()
      let expectedResponse = createTestResponse(statusCode: statusCode)

      let _ = try await interceptor.intercept(request) { _ in
        return expectedResponse
      }

      XCTAssertTrue(
        logger.verboseLogs[1].contains("Status code: \(statusCode)"),
        "Should log status code \(statusCode)"
      )
    }
  }

  // MARK: - Stringify Function Tests

  func testStringfyWithNilData() {
    let result = stringfy(nil)
    XCTAssertEqual(result, "<none>")
  }

  func testStringfyWithJSONData() {
    let jsonData = #"{"key": "value", "number": 42}"#.data(using: .utf8)!
    let result = stringfy(jsonData)

    XCTAssertTrue(result.contains("key"))
    XCTAssertTrue(result.contains("value"))
    XCTAssertTrue(result.contains("number"))
  }

  func testStringfyWithNonJSONData() {
    let textData = "Plain text content".data(using: .utf8)!
    let result = stringfy(textData)

    XCTAssertEqual(result, "Plain text content")
  }

  func testStringfyWithInvalidUTF8Data() {
    // Invalid UTF-8 sequence
    let invalidData = Data([0xFF, 0xFE, 0xFD])
    let result = stringfy(invalidData)

    XCTAssertEqual(result, "<failed>")
  }

  func testStringfyWithEmptyData() {
    let emptyData = Data()
    let result = stringfy(emptyData)

    // Empty JSON object or empty string
    XCTAssertTrue(result.isEmpty)
  }

  func testStringfyWithComplexJSON() {
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

    let result = stringfy(complexJSON)

    XCTAssertTrue(result.contains("users"))
    XCTAssertTrue(result.contains("Alice"))
    XCTAssertTrue(result.contains("nested"))
  }

  func testStringfyWithArrayJSON() {
    let arrayJSON = #"[1, 2, 3, 4, 5]"#.data(using: .utf8)!
    let result = stringfy(arrayJSON)

    XCTAssertTrue(result.contains("1"))
    XCTAssertTrue(result.contains("5"))
  }

  func testStringfyWithBooleanJSON() {
    let boolJSON = #"{"active": true, "deleted": false}"#.data(using: .utf8)!
    let result = stringfy(boolJSON)

    XCTAssertTrue(result.contains("active"))
    XCTAssertTrue(result.contains("true") || result.contains("1"))
  }

  func testStringfyWithNullJSON() {
    let nullJSON = #"{"value": null}"#.data(using: .utf8)!
    let result = stringfy(nullJSON)

    XCTAssertTrue(result.contains("value"))
  }

  // MARK: - Integration Tests

  func testInterceptorPassesThroughResponse() async throws {
    let logger = MockLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    let request = createTestRequest()
    let testData = "Test Response".data(using: .utf8)!
    let expectedResponse = createTestResponse(statusCode: 201, data: testData)

    let actualResponse = try await interceptor.intercept(request) { _ in
      return expectedResponse
    }

    // Verify response is passed through unchanged
    XCTAssertEqual(actualResponse.statusCode, 201)
    XCTAssertEqual(actualResponse.data, testData)
  }

  func testInterceptorPassesThroughError() async throws {
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
      XCTFail("Should have thrown error")
    } catch let error as CustomError {
      XCTAssertEqual(error, expectedError)
    } catch {
      XCTFail("Wrong error type thrown")
    }
  }
}
