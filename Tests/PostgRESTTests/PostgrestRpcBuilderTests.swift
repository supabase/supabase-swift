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
}
