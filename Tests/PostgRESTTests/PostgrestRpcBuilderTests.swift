//
//  PostgrestRpcBuilderTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/01/25.
//

import Foundation
import PostgREST
import TestHelpers
import Testing

@Suite
struct PostgrestRpcBuilderTests {
  let fixture = try! PostgrestQueryFixture()
  var transport: RecordingTransport { fixture.transport }
  var url: URL { fixture.url }
  var sut: PostgrestClient { fixture.sut }

  @Test
  func rpc() async throws {
    transport.stub(
      .post, url.appendingPathComponent("rpc/list_stored_countries"),
      data: Data(
        """
        {
          "id": 1,
          "name": "France"
        }
        """.utf8)
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Accept: application/vnd.pgrst.object+json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/rpc/list_stored_countries?id=eq.1"
      """#
    }

    let country =
      try await sut
      .rpc("list_stored_countries")
      .eq("id", value: 1)
      .single()
      .execute()
      .value as JSONObject

    #expect(country["name"]?.stringValue == "France")
  }

  @Test
  func rpcReadOnly() async throws {
    transport.stub(
      .get, url.appendingPathComponent("rpc/hello_world"), data: Data("Hello World".utf8)
    ) {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/rpc/hello_world"
      """#
    }

    try await sut
      .rpc("hello_world", get: true)
      .execute()
  }

  @Test
  func rpcWithGetMethodAndNonJSONObjectShouldThrowError() async throws {
    do {
      try await sut
        .rpc("hello", params: [1, 2, 3], get: true)
        .execute()
      Issue.record("Expected error to be thrown")
    } catch let error as PostgrestError {
      #expect(error.kind == .invalidRequest)
      #expect(
        error.message == "Params should be a key-value type when using `GET` or `HEAD` options.")
    }
  }

  @Test
  func rpcWithHeadMethodAndNonJSONObjectShouldThrowError() async throws {
    do {
      try await sut
        .rpc("hello", params: [1, 2, 3], head: true)
        .execute()
      Issue.record("Expected error to be thrown")
    } catch let error as PostgrestError {
      #expect(error.kind == .invalidRequest)
      #expect(
        error.message == "Params should be a key-value type when using `GET` or `HEAD` options.")
    }
  }

  @Test
  func rpcWithGetMethodAndJSONObjectShouldCleanArray() async throws {
    transport.stub(
      .get, url.appendingPathComponent("rpc/sum"),
      data: Data(
        """
        {
          "sum": 6
        }
        """.utf8
      )
    ) {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/rpc/sum?key=value&numbers=%7B1,2,3%7D"
      """#
    }

    struct Response: Decodable {
      let sum: Int
    }

    let response =
      try await sut
      .rpc(
        "sum",
        params: [
          "numbers": [1, 2, 3],
          "key": "value",
        ] as JSONObject,
        get: true
      )
      .execute()
      .value as Response

    #expect(response.sum == 6)
  }

  @Test
  func rpcWithGetMethodEncodesScalarParamsByJSONType() async throws {
    transport.stub(.get, url.appendingPathComponent("rpc/scalar"), data: Data("{}".utf8)) {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/rpc/scalar?disabled=false&enabled=true&flags=%7Btrue,false,null%7D&maybe=null&nested=%7B%22a%22:1%7D&number=42"
      """#
    }

    try await sut
      .rpc(
        "scalar",
        params: [
          "enabled": true,
          "disabled": false,
          "number": 42,
          "maybe": .null,
          "nested": ["a": 1],
          "flags": [true, false, .null],
        ] as JSONObject,
        get: true
      )
      .execute()
  }

  @Test
  func rpcWithGetMethodQuotesArrayElements() async throws {
    transport.stub(.get, url.appendingPathComponent("rpc/tagged"), data: Data("{}".utf8)) {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/rpc/tagged?tags=%7B%22Paris,%20France%22,Oslo,%22%22,%22NULL%22,%22a%5C%22b%22,%22%7Bx%7D%22%7D"
      """#
    }

    try await sut
      .rpc(
        "tagged",
        params: [
          "tags": ["Paris, France", "Oslo", "", "NULL", "a\"b", "{x}"]
        ] as JSONObject,
        get: true
      )
      .execute()
  }

  @Test
  func rpcWithCount() async throws {
    transport.stub(.post, url.appendingPathComponent("rpc/hello")) {
      #"""
      curl \
      	--request POST \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "Prefer: count=estimated" \
      	--header "X-Client-Info: postgrest-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/rpc/hello"
      """#
    }

    try await sut.rpc("hello", count: .estimated).execute()
  }

  @Test
  func rpcWithCountKeepsClientPreferHeader() async throws {
    let capture = try QueryCapture()
    var configuration = capture.client.configuration
    configuration.headers[HTTPField.Name("Prefer")!] = "tx=rollback"
    let client = try PostgrestClient(configuration: configuration)

    try await client.rpc("hello", count: .estimated).execute()

    #expect(capture.header("Prefer") == "tx=rollback,count=estimated")
  }

  @Test
  func rpcWithCountReplacesClientCountPreference() async throws {
    let capture = try QueryCapture()
    var configuration = capture.client.configuration
    configuration.headers[HTTPField.Name("Prefer")!] = "tx=rollback, count=estimated"
    let client = try PostgrestClient(configuration: configuration)

    try await client.rpc("hello", count: .exact).execute()

    #expect(capture.header("Prefer") == "tx=rollback,count=exact")
  }
}
