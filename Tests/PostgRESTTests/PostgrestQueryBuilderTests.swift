//
//  PostgrestQueryBuilderTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/01/25.
//

import InlineSnapshotTesting
import Mocker
import PostgREST
import TestHelpers
import XCTest

final class PostgrestQueryBuilderTests: PostgrestQueryTests {
  override func setUp() {
    super.setUp()
    //    isRecording = true
  }

  func testSetAuth() {
    XCTAssertNil(sut.configuration.headers["Authorization"])
    sut.setAuth("token")
    XCTAssertEqual(sut.configuration.headers["Authorization"], "Bearer token")

    sut.setAuth(nil)
    XCTAssertNil(sut.configuration.headers["Authorization"])
  }

  func testSelect() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .get: Data(
          """
          [
            {
              "id": 1,
              "username": "supabase"
            }
          ]
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
      	"http://localhost:54321/rest/v1/users?select=*"
      """#
    }
    .register()

    let users =
      try await sut
      .from("users")
      .select()
      .execute()
      .value as [User]

    XCTAssertEqual(users[0].id, 1)
    XCTAssertEqual(users[0].username, "supabase")
  }

  func testSelectWithWhitespaceInQuery() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .get: Data()
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?select=somecolumn"
      """#
    }
    .register()

    try await sut
      .from("users")
      .select("some column")
      .execute()
  }

  func testSelectWithQuoteInQuery() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .get: Data()
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?select=some%22column%22"
      """#
    }
    .register()

    try await sut
      .from("users")
      .select(#"some "column""#)
      .execute()
  }

  func testSelectWithCount() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .head: Data()
      ],
      additionalHeaders: [
        "Content-Range": "0-9/10"
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--head \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "Prefer: count=exact" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?select=*"
      """#
    }
    .register()

    let count =
      try await sut
      .from("users")
      .select(head: true, count: .exact)
      .execute()
      .count

    XCTAssertEqual(count, 10)
  }

  func testInsert() async throws {
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
      	--header "Content-Length: 59" \
      	--header "Content-Type: application/json" \
      	--header "Prefer: return=minimal,count=estimated" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "[{\"id\":1,\"username\":\"supabase\"},{\"id\":1,\"username\":\"supa\"}]" \
      	"http://localhost:54321/rest/v1/users?columns=id,username"
      """#
    }
    .register()

    try await sut
      .from("users")
      .insert(
        [
          User(id: 1, username: "supabase"),
          User(id: 1, username: "supa"),
        ],
        returning: .minimal,
        count: .estimated
      )
      .execute()
  }

  func testInsertWithExistingPreferHeader() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
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
      	--header "Content-Length: 30" \
      	--header "Content-Type: application/json" \
      	--header "Prefer: existing=value,return=minimal" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"id\":1,\"username\":\"supabase\"}" \
      	"http://localhost:54321/rest/v1/users"
      """#
    }
    .register()

    try await sut
      .from("users")
      .setHeader(name: "Prefer", value: "existing=value")
      .insert(User(id: 1, username: "supabase"), returning: .minimal)
      .execute()
  }

  func testUpdate() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 201,
      data: [
        .patch: Data()
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request PATCH \
      	--header "Accept: application/json" \
      	--header "Content-Length: 24" \
      	--header "Content-Type: application/json" \
      	--header "Prefer: existing=value,return=minimal,count=planned" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"username\":\"supabase2\"}" \
      	"http://localhost:54321/rest/v1/users?id=eq.1"
      """#
    }
    .register()

    try await sut
      .from("users")
      .setHeader(name: "Prefer", value: "existing=value")
      .update(["username": "supabase2"], returning: .minimal, count: .planned)
      .eq("id", value: 1)
      .execute()
  }

  func testUpsert() async throws {
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
      	--header "Content-Length: 60" \
      	--header "Content-Type: application/json" \
      	--header "Prefer: existing=value,resolution=merge-duplicates,return=minimal,count=estimated" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "[{\"id\":1,\"username\":\"admin\"},{\"id\":2,\"username\":\"supabase\"}]" \
      	"http://localhost:54321/rest/v1/users?columns=id,username&on_conflict=username"
      """#
    }
    .register()

    try await sut
      .from("users")
      .setHeader(name: "Prefer", value: "existing=value")
      .upsert(
        [
          User(id: 1, username: "admin"),
          User(id: 2, username: "supabase"),
        ],
        onConflict: "username",
        returning: .minimal,
        count: .estimated
      )
      .execute()
  }

  func testUpsertIgnoreDuplicates() async throws {
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
      	--header "Content-Length: 27" \
      	--header "Content-Type: application/json" \
      	--header "Prefer: resolution=ignore-duplicates,return=representation" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"id\":1,\"username\":\"admin\"}" \
      	"http://localhost:54321/rest/v1/users"
      """#
    }
    .register()

    try await sut
      .from("users")
      .upsert(User(id: 1, username: "admin"), ignoreDuplicates: true)
      .execute()
  }

  func testDelete() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 204,
      data: [
        .delete: Data()
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request DELETE \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "Prefer: existing=value,return=representation,count=estimated" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?username=eq.supabase"
      """#
    }
    .register()

    try await sut
      .from("users")
      .setHeader(name: "Prefer", value: "existing=value")
      .delete(count: .estimated)
      .eq("username", value: "supabase")
      .execute()
  }
}
