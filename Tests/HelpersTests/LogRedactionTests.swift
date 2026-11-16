import Foundation
import HTTPTypes
import Testing

@testable import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct LogRedactionTests {
  typealias MockLogger = LoggerInterceptorTests.MockLogger

  func response(data: Data = Data()) -> Helpers.HTTPResponse {
    let urlResponse = HTTPURLResponse(
      url: URL(string: "https://api.example.com/test")!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: nil
    )!
    return Helpers.HTTPResponse(data: data, response: urlResponse)
  }

  @Test
  func interceptorDoesNotLogQueryOrFragment() async throws {
    let logger = MockLogger()
    let interceptor = LoggerInterceptor(logger: logger)
    let request = Helpers.HTTPRequest(
      url: URL(
        string:
          "https://api.example.com/storage/v1/object/upload/sign/bucket/file.png?token=SECRET#frag"
      )!,
      method: .put
    )

    _ = try await interceptor.intercept(request) { _ in response() }

    let requestLog = logger.verboseLogs[0]
    #expect(
      requestLog.contains("https://api.example.com/storage/v1/object/upload/sign/bucket/file.png"))
    #expect(!requestLog.contains("SECRET"))
    #expect(!requestLog.contains("token="))
    #expect(!requestLog.contains("frag"))
  }

  @Test
  func interceptorRedactsSecretsInRequestAndResponseBodies() async throws {
    let logger = MockLogger()
    let interceptor = LoggerInterceptor(logger: logger)
    let requestBody = Data(#"{"email": "a@b.c", "password": "hunter2"}"#.utf8)
    let responseBody = Data(
      #"""
      {
        "access_token": "AT-SECRET",
        "refresh_token": "RT-SECRET",
        "user": {"id": "42", "email": "a@b.c"},
        "identities": [{"provider_token": "PT-SECRET"}],
        "signedURL": "/object/sign/bucket/file?token=SIGNED"
      }
      """#.utf8)
    let request = Helpers.HTTPRequest(
      url: URL(string: "https://api.example.com/auth/v1/token")!,
      method: .post,
      body: requestBody
    )

    _ = try await interceptor.intercept(request) { _ in response(data: responseBody) }

    let requestLog = logger.verboseLogs[0]
    #expect(!requestLog.contains("hunter2"))
    #expect(requestLog.contains(#""password" : "<redacted>""#))
    #expect(requestLog.contains("a@b.c"))

    let responseLog = logger.verboseLogs[1]
    for secret in ["AT-SECRET", "RT-SECRET", "PT-SECRET", "SIGNED"] {
      #expect(!responseLog.contains(secret))
    }
    #expect(responseLog.contains(#""access_token" : "<redacted>""#))
    #expect(responseLog.contains(#""id" : "42""#))
  }

  @Test
  func interceptorDoesNotLogTheURLOfAURLError() async throws {
    let logger = MockLogger()
    let interceptor = LoggerInterceptor(logger: logger)
    let url = URL(string: "https://api.example.com/x?token=SECRET")!
    let request = Helpers.HTTPRequest(url: url, method: .get)

    await #expect(throws: URLError.self) {
      try await interceptor.intercept(request) { _ in
        throw URLError(.timedOut, userInfo: [NSURLErrorFailingURLErrorKey: url])
      }
    }

    #expect(logger.errorLogs.count == 1)
    #expect(!logger.errorLogs[0].contains("SECRET"))
    #expect(logger.errorLogs[0].contains("\(URLError.timedOut.rawValue)"))
  }

  @Test(arguments: ["refresh_token", "refreshToken", "REFRESH-TOKEN", "otp", "apikey", "url"])
  func isSensitiveMatchesKeySpellings(key: String) {
    #expect(LogRedaction.isSensitive(jsonKey: key))
  }

  @Test(arguments: ["email", "id", "token_type", "expires_in"])
  func isSensitiveKeepsOtherKeys(key: String) {
    #expect(!LogRedaction.isSensitive(jsonKey: key))
  }
}
