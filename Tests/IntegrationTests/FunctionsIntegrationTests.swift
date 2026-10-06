//
//  FunctionsIntegrationTests.swift
//  IntegrationTests
//
//  Created by Guilherme Souza on 06/10/26.
//

import Foundation
import Functions
import HTTPTypes
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Runs against the `echo` and `stream` functions in `supabase/functions`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct FunctionsIntegrationTests {
  struct Echo: Decodable {
    var method: String
    var path: String
    var query: [String: String]
    var headers: [String: String]
    var body: String

    var bodyData: Data { Data(base64Encoded: body) ?? Data() }
  }

  static func client(
    apikey: String? = DotEnv.supabasePublishableKey,
    accessToken: (@Sendable () async throws -> String?)? = { DotEnv.supabasePublishableKey }
  ) -> FunctionsClient {
    var headers: HTTPFields = [:]
    if let apikey { headers[HTTPField.Name("apikey")!] = apikey }
    return FunctionsClient(
      configuration: .init(
        url: URL(string: "\(DotEnv.supabaseURL)/functions/v1")!,
        headers: headers,
        accessToken: accessToken
      )
    )
  }

  let client = Self.client()

  @Test
  func jsonBodyRoundTrips() async throws {
    let echo: Echo = try await client.invoke("echo", body: .json(["hi": 1]))
    #expect(echo.method == "POST")
    #expect(echo.path == "/echo")
    #expect(echo.headers["content-type"] == "application/json")
    #expect(echo.headers["authorization"] == "Bearer")
    #expect(try JSONDecoder().decode([String: Int].self, from: echo.bodyData) == ["hi": 1])
  }

  @Test
  func textBodyRoundTrips() async throws {
    let echo: Echo = try await client.invoke("echo", body: .text("hello"))
    #expect(echo.headers["content-type"] == "text/plain; charset=utf-8")
    #expect(String(decoding: echo.bodyData, as: UTF8.self) == "hello")
  }

  @Test
  func dataBodyRoundTrips() async throws {
    let bytes = Data((0..<256).map(UInt8.init))
    let echo: Echo = try await client.invoke("echo", body: .data(bytes, contentType: "image/png"))
    #expect(echo.headers["content-type"] == "image/png")
    #expect(echo.bodyData == bytes)
  }

  @Test
  func streamedBodyRoundTrips() async throws {
    let bytes = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0) })
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try bytes.write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let echo: Echo = try await client.invoke(
      "echo", body: .stream(try HTTPBody(fileURL: fileURL), contentType: "audio/m4a"))
    #expect(echo.headers["content-type"] == "audio/m4a")
    #expect(echo.bodyData == bytes)
  }

  @Test
  func getWithQuery() async throws {
    let echo: Echo = try await client.invoke(
      "echo",
      options: .init(method: .get, query: [URLQueryItem(name: "month", value: "2026-09")]))
    #expect(echo.method == "GET")
    #expect(echo.query == ["month": "2026-09"])
    #expect(echo.bodyData.isEmpty)
  }

  @Test
  func subPathAndRegionReachTheFunction() async throws {
    let echo: Echo = try await client.invoke(
      "echo/sub/path", options: .init(region: .euWest1))
    #expect(echo.path == "/echo/sub/path")
    #expect(echo.headers["x-region"] == "eu-west-1")
    #expect(echo.query["forceFunctionRegion"] == "eu-west-1")
  }

  @Test
  func rawResponseCarriesStatusAndHeaders() async throws {
    let response = try await client.invoke("echo", body: .text("x"))
    #expect(response.status == .ok)
    #expect(response.contentType?.hasPrefix("application/json") == true)
    #expect(try response.decode(as: Echo.self).method == "POST")
  }

  // The local edge runtime answers a 404 without `sb-error-code`; the hosted gateway adds
  // `NOT_FOUND`. Either way the kind is `.server` and the status is on the response.
  @Test
  func unknownSlugIsServerError() async throws {
    let error = await #expect(throws: FunctionsError.self) {
      try await client.invoke("does-not-exist")
    }
    #expect(error?.kind == .server)
    #expect(error?.response?.statusCode == 404)
  }

  @Test
  func missingAuthorizationIsPlatformError() async throws {
    let client = Self.client(apikey: nil, accessToken: nil)
    let error = await #expect(throws: FunctionsError.self) {
      try await client.invoke("echo")
    }
    #expect(error?.kind == .server)
    #expect(error?.response?.statusCode == 401)
    #expect(error?.code == .unauthorizedNoAuthHeader)
    #expect(error?.isPlatformError == true)
  }

  @Test
  func newFormatPublishableKeyPassesVerifyJWTWithoutSession() async throws {
    let client = Self.client(apikey: DotEnv.supabaseNewFormatPublishableKey, accessToken: nil)
    let echo: Echo = try await client.invoke("echo")
    #expect(echo.headers["authorization"] == nil)
  }

  @Test
  func streamYieldsThreeEvents() async throws {
    let response = try await client.stream("stream", options: .init(method: .get))
    #expect(response.status == .ok)
    #expect(response.contentType == "text/event-stream")

    let text = String(
      decoding: try await Data(collecting: response.body, upTo: .max), as: UTF8.self)
    let events = text.split(separator: "\n\n").map(String.init)
    #expect(events.count == 3)
    #expect(
      events.map { $0.split(separator: "\n").last } == [
        "data: {\"n\":1}", "data: {\"n\":2}", "data: {\"n\":3}",
      ])
  }

  @Test
  func cancellingMidStreamCancelsTheRequest() async throws {
    let clock = ContinuousClock()
    let task = Task {
      // 40 events, 50 ms apart: two seconds if the loop runs to the end.
      let response = try await client.stream(
        "stream",
        options: .init(
          method: .get,
          query: [
            URLQueryItem(name: "count", value: "40"), URLQueryItem(name: "delay", value: "50"),
          ]
        ))
      for try await _ in response.body {
        withUnsafeCurrentTask { $0?.cancel() }
      }
    }
    let start = clock.now
    await #expect(throws: CancellationError.self) { try await task.value }
    // On Linux the transport buffers the body, so the first chunk is also the last (SDK-1839).
    #if !canImport(FoundationNetworking)
      #expect(clock.now - start < .seconds(1))
    #endif
  }
}
