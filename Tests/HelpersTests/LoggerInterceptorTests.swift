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

  final class LogCapture: @unchecked Sendable {
    var lines: [(level: Logging.Logger.Level, message: String)] = []
    var messages: [String] { lines.map(\.message) }
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
      capture.lines.append((level, "\(message)"))
    }
  }

  func makeLogger(level: Logging.Logger.Level = .trace) -> (Logging.Logger, LogCapture) {
    let capture = LogCapture()
    var logger = Logging.Logger(label: "test") { _ in CapturingLogHandler(capture: capture) }
    logger.logLevel = level
    return (logger, capture)
  }

  func createTestRequest(
    url: String = "https://api.example.com/test",
    method: Method = .get
  ) -> HTTPTypes.HTTPRequest {
    HTTPTypes.HTTPRequest(method: method, url: URL(string: url)!)
  }

  func createTestResponse(statusCode: Int = 200) -> HTTPTypes.HTTPResponse {
    HTTPTypes.HTTPResponse(status: HTTPTypes.HTTPResponse.Status(code: statusCode))
  }

  @Test
  func aRequestLogsOneDebugLineWithItsOutcomeAndTiming() async throws {
    let (logger, capture) = makeLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    _ = try await interceptor.intercept(
      createTestRequest(url: "https://api.example.com/users", method: .post), body: nil
    ) { _, _ in
      (self.createTestResponse(statusCode: 201), nil)
    }

    #expect(capture.lines.count == 1)
    #expect(capture.lines.first?.level == .debug)
    let line = try #require(capture.messages.first)
    #expect(line.hasPrefix("POST https://api.example.com/users -> 201 in "))
    #expect(line.hasSuffix(" ms"))
  }

  @Test
  func aFailureLogsADebugLineAndNotAnError() async throws {
    let (logger, capture) = makeLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    struct TestError: Error {}

    await #expect(throws: TestError.self) {
      _ = try await interceptor.intercept(self.createTestRequest(), body: nil) { _, _ in
        throw TestError()
      }
    }

    #expect(capture.lines.count == 1)
    #expect(capture.lines.first?.level == .debug)
    #expect(
      capture.messages.first?.hasPrefix("GET https://api.example.com/test failed in ") == true)
  }

  @Test
  func aFailureLogsAnSDKSummaryAndNotTheFailingURL() async throws {
    let (logger, capture) = makeLogger()
    let interceptor = LoggerInterceptor(logger: logger)
    let signedURL = "https://x.supabase.co/storage/v1/object/upload/sign/b/f?token=st-secret-1"

    await #expect(throws: URLError.self) {
      _ = try await interceptor.intercept(self.createTestRequest(), body: nil) { _, _ in
        throw URLError(
          .timedOut,
          userInfo: [
            NSURLErrorFailingURLStringErrorKey: signedURL,
            NSURLErrorFailingURLErrorKey: URL(string: signedURL)!,
          ])
      }
    }

    let line = try #require(capture.messages.first)
    #expect(line.hasSuffix(": NSURLErrorDomain \(URLError.timedOut.rawValue)"))
    #expect(!line.contains("st-secret"))
  }

  @Test
  func aTransportErrorLogsItsCodeAndNotItsDescription() async throws {
    let (logger, capture) = makeLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    struct TransportError: Error, CustomStringConvertible {
      var description: String { "upstream body: private-record" }
    }

    await #expect(throws: TransportError.self) {
      _ = try await interceptor.intercept(self.createTestRequest(), body: nil) { _, _ in
        throw TransportError()
      }
    }

    let line = try #require(capture.messages.first)
    #expect(line.contains("TransportError"))
    #expect(!line.contains("private-record"))
  }

  @Test
  func theLineDropsTheQueryAndFragment() async throws {
    let (logger, capture) = makeLogger()
    let interceptor = LoggerInterceptor(logger: logger)
    let request = createTestRequest(
      url: "https://api.example.com/rest/v1/my%20invites?code=eq.pg%20secret%20one#frag")

    _ = try await interceptor.intercept(request, body: nil) { _, _ in
      (self.createTestResponse(), nil)
    }

    #expect(
      capture.messages.first?.hasPrefix("GET https://api.example.com/rest/v1/my invites -> 200")
        == true)
    #expect(!capture.messages.contains { $0.contains("secret") || $0.contains("frag") })
  }

  @Test
  func noBodyOrHeaderValueReachesTheLog() async throws {
    let (logger, capture) = makeLogger()
    let interceptor = LoggerInterceptor(logger: logger)
    var request = createTestRequest(method: .post)
    request.headerFields[.authorization] = "Bearer header-secret"

    _ = try await interceptor.intercept(
      request, body: HTTPBody(Data(#"{"name":"request-payload"}"#.utf8))
    ) { _, _ in
      (
        HTTPTypes.HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]),
        HTTPBody(Data(#"{"name":"response-payload"}"#.utf8))
      )
    }

    let logged = capture.messages.joined(separator: "\n")
    #expect(!logged.isEmpty)
    for secret in ["header-secret", "request-payload", "response-payload", "application/json"] {
      #expect(!logged.contains(secret))
    }
  }

  @Test
  func belowDebugNothingIsLogged() async throws {
    let (logger, capture) = makeLogger(level: .info)
    let interceptor = LoggerInterceptor(logger: logger)

    _ = try await interceptor.intercept(createTestRequest(), body: nil) { _, _ in
      (self.createTestResponse(), nil)
    }

    #expect(capture.lines.isEmpty)
  }

  @Test
  func interceptorWithDifferentMethodsAndStatusCodes() async throws {
    let cases: [(Method, String, Int)] = [
      (.get, "GET", 200),
      (.post, "POST", 201),
      (.put, "PUT", 400),
      (.delete, "DELETE", 404),
      (.patch, "PATCH", 500),
    ]

    for (method, methodString, statusCode) in cases {
      let (logger, capture) = makeLogger()
      let interceptor = LoggerInterceptor(logger: logger)

      _ = try await interceptor.intercept(createTestRequest(method: method), body: nil) { _, _ in
        (self.createTestResponse(statusCode: statusCode), nil)
      }

      #expect(
        capture.messages.first?.hasPrefix(
          "\(methodString) https://api.example.com/test -> \(statusCode) in ") == true)
    }
  }

  @Test
  func theResponseBodyPassesThroughUnread() async throws {
    let (logger, _) = makeLogger()
    let interceptor = LoggerInterceptor(logger: logger)
    let body = HTTPBody(Data("Test Response".utf8))

    let (head, returned) = try await interceptor.intercept(createTestRequest(), body: nil) {
      _, _ in
      (self.createTestResponse(statusCode: 201), body)
    }

    #expect(head.status.code == 201)
    #expect(returned === body)
  }

  @Test
  func theRequestBodyPassesThroughUnread() async throws {
    let (logger, _) = makeLogger()
    let interceptor = LoggerInterceptor(logger: logger)
    let body = HTTPBody(Data(#"{"name": "test"}"#.utf8))
    let forwarded = LockIsolated<HTTPBody?>(nil)

    _ = try await interceptor.intercept(createTestRequest(method: .post), body: body) {
      _, next in
      forwarded.setValue(next)
      return (self.createTestResponse(), nil)
    }

    #expect(forwarded.value === body)
  }

  @Test
  func interceptorPassesThroughError() async throws {
    let (logger, _) = makeLogger()
    let interceptor = LoggerInterceptor(logger: logger)

    struct CustomError: Error, Equatable {
      let message: String
    }

    let expectedError = CustomError(message: "Test error")

    await #expect(throws: expectedError) {
      _ = try await interceptor.intercept(self.createTestRequest(), body: nil) { _, _ in
        throw expectedError
      }
    }
  }
}
