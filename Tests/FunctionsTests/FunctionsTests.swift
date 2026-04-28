//
//  FunctionsTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 13/03/26.
//

import Foundation
import Functions
import Helpers
import Replay
import Testing

// Resolved once at module init; used by each @Test trait to build the archive path
// directly via ReplayTrait.rootURL (step 1 of getArchiveURL), bypassing both
// ReplayTestDefaults and Bundle.url(forResource:subdirectory:) which is broken on Linux.
private let _replaysURL: URL? = Bundle.module.resourceURL?.appendingPathComponent("Replays")

@Suite
struct FunctionsTests {

  let client = FunctionsClient(
    url: URL(string: "http://127.0.0.1:54321/functions/v1")!,
    headers: [
      "apikey": "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
    ],
    session: Replay.session
  )

  // MARK: - Basic Invocation Tests

  @Test(ReplayTrait("invoke_default", rootURL: _replaysURL))
  func invokeDefault() async throws {
    let (response, _): (AnyJSON, _) = try await client.invokeDecodable("echo")

    // Verify the request was a POST with no body
    let method = response.objectValue?["method"]?.stringValue
    #expect(method == "POST")

    let body = response.objectValue?["body"]
    #expect(body?.isNil == true)
  }

  @Test(ReplayTrait("invoke_with_json_body", rootURL: _replaysURL))
  func invokeWithJSONBody() async throws {
    struct RequestBody: Codable {
      let message: String
      let count: Int
      let active: Bool
    }

    let (response, _): (AnyJSON, _) =
      try await client.invokeDecodable("echo") {
        $0.body = try! JSONEncoder().encode(
          RequestBody(message: "Hello from Swift", count: 42, active: true)
        )
        $0.headers["Content-Type"] = "application/json"
      }

    // Verify body was sent correctly
    let body = response.objectValue?["body"]?.objectValue
    #expect(body?["message"]?.stringValue == "Hello from Swift")
    #expect(body?["count"]?.intValue == 42)
    #expect(body?["active"]?.boolValue == true)

    // Verify content-type header
    let headers = response.objectValue?["headers"]?.objectValue
    #expect(headers?["content-type"]?.stringValue == "application/json")
  }

  @Test(ReplayTrait("invoke_with_json_array", rootURL: _replaysURL))
  func invokeWithJSONArray() async throws {
    let items = ["apple", "banana", "cherry"]

    let (response, _): (AnyJSON, _) =
      try await client.invokeDecodable("echo") {
        $0.body = try! JSONEncoder().encode(items)
        $0.headers["Content-Type"] = "application/json"
      }

    // Verify array body
    let body = response.objectValue?["body"]?.arrayValue?.compactMap {
      $0.stringValue
    }
    #expect(body == items)
  }

  @Test(ReplayTrait("invoke_with_plain_text", rootURL: _replaysURL))
  func invokeWithPlainText() async throws {
    let text = "This is plain text content"

    let (response, _): (AnyJSON, _) =
      try await client.invokeDecodable("echo") {
        $0.body = Data(text.utf8)
        $0.headers["Content-Type"] = "text/plain"
      }

    // Verify text body
    let body = response.objectValue?["body"]?.stringValue
    #expect(body == text)

    // Verify content-type header
    let headers = response.objectValue?["headers"]?.objectValue
    #expect(headers?["content-type"]?.stringValue == "text/plain")
  }

  @Test(ReplayTrait("invoke_with_binary_data", rootURL: _replaysURL))
  func invokeWithBinaryData() async throws {
    let data = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F])  // "Hello" in UTF-8

    let (response, _): (AnyJSON, _) =
      try await client.invokeDecodable("echo") {
        $0.body = data
        $0.headers["Content-Type"] = "application/octet-stream"
      }

    // Verify data was sent (echo will return it as string or data)
    let body = response.objectValue?["body"]
    #expect(body?.isNil == false)

    // Verify content-type header
    let headers = response.objectValue?["headers"]?.objectValue
    #expect(
      headers?["content-type"]?.stringValue == "application/octet-stream"
    )
  }

  // MARK: - HTTP Method Tests

  @Test(ReplayTrait("invoke_get_method", rootURL: _replaysURL))
  func invokeGETMethod() async throws {
    let (response, _): (AnyJSON, _) =
      try await client.invokeDecodable("echo") { $0.method = .get }

    let method = response.objectValue?["method"]?.stringValue
    #expect(method == "GET")

    // GET requests should not have a body
    let body = response.objectValue?["body"]
    #expect(body?.isNil == true)
  }

  @Test(ReplayTrait("invoke_put_method", rootURL: _replaysURL))
  func invokePUTMethod() async throws {
    let (response, _): (AnyJSON, _) =
      try await client.invokeDecodable("echo") {
        $0.method = .put
        $0.body = try! JSONEncoder().encode(["update": "data"])
        $0.headers["Content-Type"] = "application/json"
      }

    let method = response.objectValue?["method"]?.stringValue
    #expect(method == "PUT")
  }

  @Test(ReplayTrait("invoke_patch_method", rootURL: _replaysURL))
  func invokePATCHMethod() async throws {
    let (response, _): (AnyJSON, _) =
      try await client.invokeDecodable("echo") {
        $0.method = .patch
        $0.body = try! JSONEncoder().encode(["field": "value"])
        $0.headers["Content-Type"] = "application/json"
      }

    let method = response.objectValue?["method"]?.stringValue
    #expect(method == "PATCH")
  }

  @Test(ReplayTrait("invoke_delete_method", rootURL: _replaysURL))
  func invokeDELETEMethod() async throws {
    let (response, _): (AnyJSON, _) =
      try await client.invokeDecodable("echo") {
        $0.method = .delete
        $0.body = try! JSONEncoder().encode(["id": "123"])
        $0.headers["Content-Type"] = "application/json"
      }

    let method = response.objectValue?["method"]?.stringValue
    #expect(method == "DELETE")
  }

  // MARK: - Query Parameters Tests

  // Note: These tests are disabled for replay due to non-deterministic query parameter
  // ordering from Swift Dictionary. When replaying, the URL query string order may differ
  // from recording, causing mismatches. These tests work correctly in live mode.

  // @Test(.replay("invoke_with_query_params"))
  // func invokeWithQueryParams() async throws {
  //   let response =
  //     try await client.invoke(
  //       "echo",
  //       options: FunctionInvokeOptions(
  //         query: [
  //           "search": "test",
  //           "page": "1",
  //           "limit": "10",
  //         ]
  //       )
  //     ) as AnyJSON
  //
  //   // Verify query parameters
  //   let query = response.objectValue?["query"]?.objectValue
  //   #expect(query?["search"]?.stringValue == "test")
  //   #expect(query?["page"]?.stringValue == "1")
  //   #expect(query?["limit"]?.stringValue == "10")
  // }
  //
  // @Test(.replay("invoke_with_special_chars_in_query"))
  // func invokeWithSpecialCharsInQuery() async throws {
  //   let response =
  //     try await client.invoke(
  //       "echo",
  //       options: FunctionInvokeOptions(
  //         query: [
  //           "email": "user@example.com",
  //           "filter": "name=John&age>25",
  //         ]
  //       )
  //     ) as AnyJSON
  //
  //   // Verify special characters are preserved
  //   let query = response.objectValue?["query"]?.objectValue
  //   #expect(query?["email"]?.stringValue == "user@example.com")
  // }

  // MARK: - Custom Headers Tests

  @Test(ReplayTrait("invoke_with_custom_headers", rootURL: _replaysURL))
  func invokeWithCustomHeaders() async throws {
    let (response, _): (AnyJSON, _) =
      try await client.invokeDecodable("echo") {
        $0.headers["X-Custom-Header"] = "custom-value"
        $0.headers["X-Request-ID"] = "req-123"
        $0.headers["X-Api-Version"] = "v1"
      }

    // Verify custom headers
    let headers = response.objectValue?["headers"]?.objectValue
    #expect(headers?["x-custom-header"]?.stringValue == "custom-value")
    #expect(headers?["x-request-id"]?.stringValue == "req-123")
    #expect(headers?["x-api-version"]?.stringValue == "v1")
  }

  @Test(ReplayTrait("invoke_with_content_type_override", rootURL: _replaysURL))
  func invokeWithContentTypeOverride() async throws {
    let (response, _): (AnyJSON, _) =
      try await client.invokeDecodable("echo") {
        $0.headers["Content-Type"] = "application/xml"
        $0.body = Data("<xml>data</xml>".utf8)
      }

    // Verify content-type was overridden
    let headers = response.objectValue?["headers"]?.objectValue
    #expect(headers?["content-type"]?.stringValue == "application/xml")
  }

  // MARK: - Complex Scenarios

  @Test(ReplayTrait("invoke_with_all_options", rootURL: _replaysURL))
  func invokeWithAllOptions() async throws {
    struct ComplexBody: Codable {
      let user: String
      let data: [String: Int]
    }

    let (response, _): (AnyJSON, _) =
      try await client.invokeDecodable("echo") {
        $0.method = .post
        $0.query["debug"] = "true"
        $0.headers["X-Test"] = "comprehensive"
        $0.body = try! JSONEncoder().encode(
          ComplexBody(
            user: "test-user",
            data: ["score": 100, "level": 5]
          )
        )
      }

    // Verify all options were applied
    #expect(response.objectValue?["method"]?.stringValue == "POST")

    let query = response.objectValue?["query"]?.objectValue
    #expect(query?["debug"]?.stringValue == "true")

    let headers = response.objectValue?["headers"]?.objectValue
    #expect(headers?["x-test"]?.stringValue == "comprehensive")

    let body = response.objectValue?["body"]?.objectValue
    #expect(body?["user"]?.stringValue == "test-user")
  }

  @Test(ReplayTrait("invoke_with_nested_json", rootURL: _replaysURL))
  func invokeWithNestedJSON() async throws {
    struct NestedData: Codable {
      let level1: Level1

      struct Level1: Codable {
        let level2: Level2
        let items: [String]

        struct Level2: Codable {
          let name: String
          let value: Int
        }
      }
    }

    let data = NestedData(
      level1: NestedData.Level1(
        level2: NestedData.Level1.Level2(name: "deep", value: 999),
        items: ["a", "b", "c"]
      )
    )

    let (response, _): (AnyJSON, _) =
      try await client.invokeDecodable("echo") {
        $0.body = try! JSONEncoder().encode(data)
      }

    // Verify nested structure
    let body = response.objectValue?["body"]?.objectValue
    let level1 = body?["level1"]?.objectValue
    let level2 = level1?["level2"]?.objectValue
    #expect(level2?["name"]?.stringValue == "deep")
    #expect(level2?["value"]?.intValue == 999)

    let items = level1?["items"]?.arrayValue?.compactMap { $0.stringValue }
    #expect(items == ["a", "b", "c"])
  }

  // MARK: - Decode Tests

  @Test(ReplayTrait("invoke_with_decode", rootURL: _replaysURL))
  func invokeWithDecode() async throws {
    struct EchoResponse: Codable {
      let method: String
      let path: String
      let query: [String: String]
    }

    let (response, _): (EchoResponse, _) = try await client.invokeDecodable(
      "echo"
    ) {
      $0.method = .get
      $0.query = ["test": "value"]
    }

    #expect(response.method == "GET")
    #expect(response.path == "/echo")
    #expect(response.query["test"] == "value")
  }

  @Test(ReplayTrait("invoke_with_custom_decoder", rootURL: _replaysURL))
  func invokeWithCustomDecoder() async throws {
    struct EchoResponse: Codable {
      let method: String
      let timestamp: Date
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let (response, _): (EchoResponse, _) = try await client.invokeDecodable(
      "echo",
      decoder: decoder
    ) { $0.method = .get }

    #expect(response.method == "GET")
    #expect(response.timestamp.timeIntervalSince1970 > 0)
  }

  // MARK: - Authentication Tests

  @Test(ReplayTrait("invoke_with_auth_token", rootURL: _replaysURL))
  func invokeWithAuthToken() async throws {
    // Use the valid anon token from supabase
    let validToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
    await client.setAuth(token: validToken)

    let (response, _): (AnyJSON, _) = try await client.invokeDecodable("echo")

    // Verify auth token is in headers
    let headers = response.objectValue?["headers"]?.objectValue
    #expect(
      headers?["authorization"]?.stringValue == "Bearer \(validToken)"
    )
  }

  // MARK: - Empty/Nil Body Tests

  @Test(ReplayTrait("invoke_with_nil_body", rootURL: _replaysURL))
  func invokeWithNilBody() async throws {
    let (response, _): (AnyJSON, _) =
      try await client.invokeDecodable("echo") { $0.method = .post }

    let body = response.objectValue?["body"]
    #expect(body?.isNil == true)
  }

  // MARK: - Response Metadata Tests

  @Test(ReplayTrait("invoke_verify_metadata", rootURL: _replaysURL))
  func invokeVerifyMetadata() async throws {
    let (response, _): (AnyJSON, _) = try await client.invokeDecodable("echo")

    // Verify all expected fields are present
    let obj = response.objectValue
    #expect(obj?["method"] != nil)
    #expect(obj?["url"] != nil)
    #expect(obj?["path"] != nil)
    #expect(obj?["query"] != nil)
    #expect(obj?["headers"] != nil)
    #expect(obj?["timestamp"] != nil)
  }

  @Test(ReplayTrait("invoke_verify_url_structure", rootURL: _replaysURL))
  func invokeVerifyURLStructure() async throws {
    let (response, _): (AnyJSON, _) =
      try await client.invokeDecodable("echo") { $0.query["param1"] = "value1" }
    let url = response.objectValue?["url"]?.stringValue
    #expect(url != nil)
    #expect(url?.contains("echo") == true)

    let path = response.objectValue?["path"]?.stringValue
    #expect(path == "/echo")
  }
}
