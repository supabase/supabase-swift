//
//  FunctionsAPITests.swift
//  Functions
//
//  Created by Guilherme Souza on 05/10/26.
//

import Foundation
import HTTPTypes
import HTTPTypesFoundation
import Helpers
import InlineSnapshotTesting
import TestHelpers
import Testing

@testable import Functions

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct FunctionsAPITests {
  let configuration = FunctionsClient.Configuration(
    url: URL(string: "http://localhost:5432/functions/v1")!,
    headers: [
      HTTPField.Name("apikey")!: "supabase.publishable.key",
      .xClientInfo: "functions-swift/x.y.z",
    ]
  )

  // MARK: Request building

  @Test
  func defaultRequest() async throws {
    try await assertRequest(name: "hello-world") {
      """
      curl \\
      	--request POST \\
      	--header "X-Client-Info: functions-swift/x.y.z" \\
      	--header "apikey: supabase.publishable.key" \\
      	"http://localhost:5432/functions/v1/hello-world"
      """
    }
  }

  @Test
  func jsonBody() async throws {
    try await assertRequest(name: "hello-world", body: .json(["name": "Supabase"])) {
      """
      curl \\
      	--request POST \\
      	--header "Content-Type: application/json" \\
      	--header "X-Client-Info: functions-swift/x.y.z" \\
      	--header "apikey: supabase.publishable.key" \\
      	--data "{\\"name\\":\\"Supabase\\"}" \\
      	"http://localhost:5432/functions/v1/hello-world"
      """
    }
  }

  @Test
  func textBody() async throws {
    try await assertRequest(name: "hello-world", body: .text("hello")) {
      """
      curl \\
      	--request POST \\
      	--header "Content-Type: text/plain; charset=utf-8" \\
      	--header "X-Client-Info: functions-swift/x.y.z" \\
      	--header "apikey: supabase.publishable.key" \\
      	--data "hello" \\
      	"http://localhost:5432/functions/v1/hello-world"
      """
    }
  }

  @Test
  func dataBody() async throws {
    try await assertRequest(name: "hello-world", body: .data(Data("raw".utf8))) {
      """
      curl \\
      	--request POST \\
      	--header "Content-Type: application/octet-stream" \\
      	--header "X-Client-Info: functions-swift/x.y.z" \\
      	--header "apikey: supabase.publishable.key" \\
      	--data "raw" \\
      	"http://localhost:5432/functions/v1/hello-world"
      """
    }
  }

  @Test
  func dataBodyWithContentType() async throws {
    try await assertRequest(
      name: "hello-world", body: .data(Data("<xml/>".utf8), contentType: "application/xml")
    ) {
      """
      curl \\
      	--request POST \\
      	--header "Content-Type: application/xml" \\
      	--header "X-Client-Info: functions-swift/x.y.z" \\
      	--header "apikey: supabase.publishable.key" \\
      	--data "<xml/>" \\
      	"http://localhost:5432/functions/v1/hello-world"
      """
    }
  }

  @Test
  func streamBody() async throws {
    try await assertRequest(
      name: "hello-world",
      body: .stream(HTTPBody(Data("chunked".utf8)), contentType: "audio/m4a")
    ) {
      """
      curl \\
      	--request POST \\
      	--header "Content-Type: audio/m4a" \\
      	--header "X-Client-Info: functions-swift/x.y.z" \\
      	--header "apikey: supabase.publishable.key" \\
      	--data "chunked" \\
      	"http://localhost:5432/functions/v1/hello-world"
      """
    }
  }

  @Test
  func perCallContentTypeWinsOverTheBody() async throws {
    try await assertRequest(
      name: "hello-world",
      body: .data(Data("x".utf8)),
      options: .init(headers: [.contentType: "multipart/form-data; boundary=abc"])
    ) {
      """
      curl \\
      	--request POST \\
      	--header "Content-Type: multipart/form-data; boundary=abc" \\
      	--header "X-Client-Info: functions-swift/x.y.z" \\
      	--header "apikey: supabase.publishable.key" \\
      	--data "x" \\
      	"http://localhost:5432/functions/v1/hello-world"
      """
    }
  }

  @Test(arguments: [HTTPRequest.Method.get, .put, .patch, .delete])
  func method(_ method: HTTPRequest.Method) {
    let (request, _) = FunctionsAPI.makeRequest(
      name: "hello-world", body: nil, options: .init(method: method), configuration: configuration)
    #expect(request.method == method)
  }

  @Test
  func getRequest() async throws {
    try await assertRequest(name: "hello-world", options: .init(method: .get)) {
      """
      curl \\
      	--header "X-Client-Info: functions-swift/x.y.z" \\
      	--header "apikey: supabase.publishable.key" \\
      	"http://localhost:5432/functions/v1/hello-world"
      """
    }
  }

  @Test
  func query() async throws {
    try await assertRequest(
      name: "hello-world",
      options: .init(query: [
        URLQueryItem(name: "key", value: "value"), URLQueryItem(name: "q", value: "a b"),
      ])
    ) {
      """
      curl \\
      	--request POST \\
      	--header "X-Client-Info: functions-swift/x.y.z" \\
      	--header "apikey: supabase.publishable.key" \\
      	"http://localhost:5432/functions/v1/hello-world?key=value&q=a%20b"
      """
    }
  }

  @Test
  func clientRegion() async throws {
    var configuration = configuration
    configuration.region = .caCentral1
    try await assertRequest(name: "hello-world", configuration: configuration) {
      """
      curl \\
      	--request POST \\
      	--header "X-Client-Info: functions-swift/x.y.z" \\
      	--header "apikey: supabase.publishable.key" \\
      	--header "x-region: ca-central-1" \\
      	"http://localhost:5432/functions/v1/hello-world?forceFunctionRegion=ca-central-1"
      """
    }
  }

  @Test
  func perCallRegion() async throws {
    try await assertRequest(name: "hello-world", options: .init(region: .apNortheast1)) {
      """
      curl \\
      	--request POST \\
      	--header "X-Client-Info: functions-swift/x.y.z" \\
      	--header "apikey: supabase.publishable.key" \\
      	--header "x-region: ap-northeast-1" \\
      	"http://localhost:5432/functions/v1/hello-world?forceFunctionRegion=ap-northeast-1"
      """
    }
  }

  @Test
  func perCallRegionWinsOverClientRegion() async throws {
    var configuration = configuration
    configuration.region = .caCentral1
    try await assertRequest(
      name: "hello-world", options: .init(region: .euCentral2), configuration: configuration
    ) {
      """
      curl \\
      	--request POST \\
      	--header "X-Client-Info: functions-swift/x.y.z" \\
      	--header "apikey: supabase.publishable.key" \\
      	--header "x-region: eu-central-2" \\
      	"http://localhost:5432/functions/v1/hello-world?forceFunctionRegion=eu-central-2"
      """
    }
  }

  @Test
  func perCallHeadersWinOverClientHeaders() async throws {
    try await assertRequest(
      name: "hello-world",
      options: .init(headers: [HTTPField.Name("apikey")!: "per-call", .xClientInfo: "app/1.0"])
    ) {
      """
      curl \\
      	--request POST \\
      	--header "X-Client-Info: app/1.0" \\
      	--header "apikey: per-call" \\
      	"http://localhost:5432/functions/v1/hello-world"
      """
    }
  }

  @Test
  func subPathName() async throws {
    try await assertRequest(name: "api/users/1") {
      """
      curl \\
      	--request POST \\
      	--header "X-Client-Info: functions-swift/x.y.z" \\
      	--header "apikey: supabase.publishable.key" \\
      	"http://localhost:5432/functions/v1/api/users/1"
      """
    }
  }

  @Test
  func clientInfoDefaultsToTheModuleVersion() {
    let (request, _) = FunctionsAPI.makeRequest(
      name: "f", body: nil, options: .init(),
      configuration: .init(url: configuration.url))
    #expect(request.headerFields[.xClientInfo] == "functions-swift/\(Functions.version)")
  }

  // MARK: Head classification

  struct HeadCase: Sendable, CustomTestStringConvertible {
    var relay = false
    var status: Int
    var code: String?
    var kind: FunctionsError.Kind?
    var expectedCode: FunctionsError.Code?
    var isPlatformError = false

    var testDescription: String {
      "\(status)\(relay ? " relay" : "")\(code.map { " \($0)" } ?? "")"
    }
  }

  @Test(arguments: [
    HeadCase(relay: true, status: 500, kind: .relay),
    HeadCase(relay: true, status: 200, kind: .relay),
    HeadCase(
      relay: true, status: 502, code: "WORKER_ERROR", kind: .relay, expectedCode: .workerError,
      isPlatformError: true),
    HeadCase(status: 200),
    HeadCase(status: 204),
    HeadCase(
      status: 404, code: "NOT_FOUND", kind: .server, expectedCode: .notFound, isPlatformError: true),
    HeadCase(status: 404, kind: .server),
    HeadCase(
      status: 500, code: "EDGE_FUNCTION_ERROR", kind: .server, expectedCode: .edgeFunctionError),
    HeadCase(
      status: 503, code: "BOOT_ERROR", kind: .server, expectedCode: .bootError,
      isPlatformError: true),
    HeadCase(
      status: 546, code: "WORKER_RESOURCE_LIMIT", kind: .server, expectedCode: .workerResourceLimit,
      isPlatformError: true),
    HeadCase(
      status: 429, code: "RATE_LIMIT_EXCEEDED", kind: .server, expectedCode: .rateLimitExceeded,
      isPlatformError: true),
    HeadCase(
      status: 401, code: "SOMETHING_NEW", kind: .server, expectedCode: "SOMETHING_NEW",
      isPlatformError: true),
  ])
  func headClassification(_ testCase: HeadCase) async {
    var head = HTTPResponse(status: .init(code: testCase.status))
    if testCase.relay { head.headerFields[.xRelayError] = "true" }
    if let code = testCase.code { head.headerFields[.sbErrorCode] = code }
    let body = HTTPBody(Data("body".utf8))

    do {
      try await FunctionsAPI.throwIfFailed(head, body: body)
      #expect(testCase.kind == nil)
    } catch let error as FunctionsError {
      #expect(error.kind == testCase.kind)
      #expect(error.code == testCase.expectedCode)
      #expect(error.isPlatformError == testCase.isPlatformError)
      #expect(error.response?.statusCode == testCase.status)
      #expect(error.response?.body == Data("body".utf8))
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  // MARK: Helpers

  private func assertRequest(
    name: String,
    body: FunctionBody? = nil,
    options: FunctionInvokeOptions = .init(),
    configuration: FunctionsClient.Configuration? = nil,
    matches expected: (() -> String)? = nil,
    fileID: StaticString = #fileID,
    file filePath: StaticString = #filePath,
    function: StaticString = #function,
    line: UInt = #line,
    column: UInt = #column
  ) async throws {
    let (request, requestBody) = FunctionsAPI.makeRequest(
      name: name, body: body, options: options, configuration: configuration ?? self.configuration)
    var urlRequest = try #require(URLRequest(httpRequest: request))
    if let requestBody { urlRequest.httpBody = try await Data(collecting: requestBody, upTo: .max) }
    #if !os(Android)
      assertInlineSnapshot(
        of: urlRequest, as: .curl, matches: expected,
        fileID: fileID, file: filePath, function: function, line: line, column: column)
    #endif
  }
}
