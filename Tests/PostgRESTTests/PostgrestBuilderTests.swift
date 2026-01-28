//
//  PostgrestBuilderTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 20/08/24.
//

import InlineSnapshotTesting
import Mocker
import XCTest

@testable import PostgREST

final class PostgrestBuilderTests: PostgrestQueryTests {
  func testCustomHeaderOnAPerCallBasis() throws {
    let url = URL(string: "http://localhost:54321/rest/v1")!
    let postgrest1 = PostgrestClient(url: url, headers: ["apikey": "foo"], logger: nil)
    let postgrest2 = try postgrest1.rpc("void_func").setHeader(name: .init("apikey")!, value: "bar")

    // Original client object isn't affected
    XCTAssertEqual(
      postgrest1.from("users").select().mutableState.request.headers[.init("apikey")!], "foo")
    // Derived client object uses new header value
    XCTAssertEqual(postgrest2.mutableState.request.headers[.init("apikey")!], "bar")
  }

  func testExecuteWithNonSuccessStatusCode() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 400,
      data: [
        .get: Data(
          """
          {
            "message": "Bad Request"
          }
          """.utf8
        )
      ]
    )
    .register()

    do {
      try await sut
        .from("users")
        .select()
        .execute()
    } catch let error as PostgrestError {
      XCTAssertEqual(error.message, "Bad Request")
    }
  }

  func testExecuteWithNonJSONError() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 400,
      data: [
        .get: Data("Bad Request".utf8)
      ]
    )
    .register()

    do {
      try await sut
        .from("users")
        .select()
        .execute()
    } catch let error as HTTPError {
      XCTAssertEqual(error.data, Data("Bad Request".utf8))
      XCTAssertEqual(error.response.statusCode, 400)
    }
  }

  func testExecuteWithHead() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .head: Data()
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--head \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?select=*"
      """#
    }
    .register()

    try await sut.from("users")
      .select()
      .execute(options: FetchOptions(head: true))
  }

  func testExecuteWithCount() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .get: Data("[]".utf8)
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "Prefer: count=exact" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?select=*"
      """#
    }
    .register()

    try await sut.from("users")
      .select()
      .execute(options: FetchOptions(count: .exact))
  }

  func testExecuteWithCustomSchema() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .get: Data("[]".utf8)
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Accept-Profile: private" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?select=*"
      """#
    }
    .register()

    try await sut
      .schema("private")
      .from("users")
      .select()
      .execute()
  }

  func testExecuteWithCustomSchemaAndHeadMethod() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .head: Data()
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--head \
      	--header "Accept: application/json" \
      	--header "Accept-Profile: private" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?select=*"
      """#
    }
    .register()

    try await sut
      .schema("private")
      .from("users")
      .select()
      .execute(options: FetchOptions(head: true))
  }

  func testExecuteWithCustomSchemaAndPostMethod() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 201,
      data: [
        .post: Data()
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Accept: application/json" \
      	--header "Content-Length: 19" \
      	--header "Content-Profile: private" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"username\":\"test\"}" \
      	"http://localhost:54321/rest/v1/users"
      """#
    }
    .register()

    try await sut
      .schema("private")
      .from("users")
      .insert(["username": "test"])
      .execute()
  }

  func testSetHeader() {
    let query = sut.from("users")
      .setHeader(name: "key", value: "value")

    XCTAssertEqual(query.mutableState.request.headers[.init("key")!], "value")
  }
}
