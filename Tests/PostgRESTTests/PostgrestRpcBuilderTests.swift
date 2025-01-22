//
//  PostgrestRpcBuilderTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/01/25.
//

import Helpers
import InlineSnapshotTesting
import Mocker
import PostgREST
import XCTest

final class PostgrestRpcBuilderTests: PostgrestQueryTests {
  func testRpc() async throws {
    Mock(
      url: url.appendingPathComponent("rpc/list_stored_countries"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .post: Data(
          """
          {
            "id": 1,
            "name": "France"
          }
          """.utf8)
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Accept: application/vnd.pgrst.object+json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/rpc/list_stored_countries?id=eq.1"
      """#
    }
    .register()

    let country =
      try await sut
      .rpc("list_stored_countries")
      .eq("id", value: 1)
      .single()
      .execute()
      .value as JSONObject

    XCTAssertEqual(country["name"]?.stringValue, "France")
  }

  func testRpcReadOnly() async throws {
    Mock(
      url: url.appendingPathComponent("rpc/hello_world"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .get: Data("Hello World".utf8)
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/rpc/hello_world"
      """#
    }
    .register()

    try await sut
      .rpc("hello_world", get: true)
      .execute()
  }

  func testRpcWithGetMethodAndNonJSONObjectShouldThrowError() async throws {
    do {
      try await sut
        .rpc("hello", params: [1, 2, 3], get: true)
        .execute()
    } catch let error as PostgrestError {
      XCTAssertEqual(
        error.message, "Params should be a key-value type when using `GET` or `HEAD` options.")
    }
  }

  func testRpcWithHeadMethodAndNonJSONObjectShouldThrowError() async throws {
    do {
      try await sut
        .rpc("hello", params: [1, 2, 3], head: true)
        .execute()
    } catch let error as PostgrestError {
      XCTAssertEqual(
        error.message, "Params should be a key-value type when using `GET` or `HEAD` options.")
    }
  }

  func testRpcWithGetMethodAndJSOBOjectShouldCleanArray() async throws {
    Mock(
      url: url.appendingPathComponent("rpc/sum"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .get: Data(
          """
          {
            "sum": 6
          }
          """.utf8
        )
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/rpc/sum?key=value&numbers=%7B1,2,3%7D"
      """#
    }
    .register()

    struct Response: Decodable {
      let sum: Int
    }

    let response =
      try await sut
      .rpc(
        "sum",
        params: [
          "numbers": [1, 2, 3],
          "key": "value"
        ] as JSONObject,
        get: true
      )
      .execute()
      .value as Response

    XCTAssertEqual(response.sum, 6)
  }

  func testRpcWithCount() async throws {
    Mock(
      url: url.appendingPathComponent("rpc/hello"),
      statusCode: 200,
      data: [.post: Data()]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "Prefer: count=estimated" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/rpc/hello"
      """#
    }
    .register()

    try await sut.rpc("hello", count: .estimated).execute()
  }
}
