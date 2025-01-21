//
//  PostgrestFilterBuilderTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/01/25.
//

import InlineSnapshotTesting
import Mocker
import PostgREST
import XCTest

final class PostgrestFilterBuilderTests: PostgrestQueryTests {

  override func setUp() {
    super.setUp()
    // isRecording = true
  }

  func testNotFilter() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?select=*&status=not.eq.OFFLINE"
      """#
    }
    .register()

    _ =
      try await sut
      .from("users")
      .select()
      .not("status", operator: .eq, value: "OFFLINE")
      .execute()
  }

  func testOrFilter() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?or=(status.eq.OFFLINE,username.eq.test)&select=*"
      """#
    }
    .register()

    _ =
      try await sut
      .from("users")
      .select()
      .or("status.eq.OFFLINE,username.eq.test")
      .execute()
  }

  func testOrFilterWithReferencedTable() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?messages.or=(public.eq.true,recipient_id.eq.1)&select=*"
      """#
    }
    .register()

    _ =
      try await sut
      .from("users")
      .select()
      .or("public.eq.true,recipient_id.eq.1", referencedTable: "messages")
      .execute()
  }

  func testContainsFilter() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?address=cs.%7B%22postcode%22:90210%7D&select=*"
      """#
    }
    .register()

    _ =
      try await sut
      .from("users")
      .select()
      .contains("address", value: ["postcode": 90210])
      .execute()
  }

  func testTextSearchFilter() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?description=fts(english).programmer&select=*"
      """#
    }
    .register()

    _ =
      try await sut
      .from("users")
      .select()
      .textSearch("description", query: "programmer", config: "english")
      .execute()
  }

  func testMultipleFilters() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?age=gte.18&select=*&status=eq.active"
      """#
    }
    .register()

    _ =
      try await sut
      .from("users")
      .select()
      .gte("age", value: 18)
      .eq("status", value: "active")
      .execute()
  }

  func testLikeFilter() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?email=like.%25@example.com&select=*"
      """#
    }
    .register()

    _ =
      try await sut
      .from("users")
      .select()
      .like("email", pattern: "%@example.com")
      .execute()
  }

  func testILikeFilter() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?email=ilike.%25@EXAMPLE.COM&select=*"
      """#
    }
    .register()

    _ =
      try await sut
      .from("users")
      .select()
      .ilike("email", pattern: "%@EXAMPLE.COM")
      .execute()
  }

  func testIsFilter() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?deleted_at=is.NULL&select=*"
      """#
    }
    .register()

    _ =
      try await sut
      .from("users")
      .select()
      .is("deleted_at", value: nil)
      .execute()
  }

  func testInFilter() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?select=*&status=in.(active,pending)"
      """#
    }
    .register()

    _ =
      try await sut
      .from("users")
      .select()
      .in("status", values: ["active", "pending"])
      .execute()
  }

  func testContainedByFilter() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?roles=cd.%7Badmin,user%7D&select=*"
      """#
    }
    .register()

    _ =
      try await sut
      .from("users")
      .select()
      .containedBy("roles", value: ["admin", "user"])
      .execute()
  }

  func testRangeFilters() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?age_range=sl.%5B18,25)&fifth_range=adj.%5B55,65)&fourth_range=nxr.%5B45,55)&other_range=sr.%5B25,35)&select=*&third_range=nxl.%5B35,45)"
      """#
    }
    .register()

    _ =
      try await sut
      .from("users")
      .select()
      .rangeLt("age_range", range: "[18,25)")
      .rangeGt("other_range", range: "[25,35)")
      .rangeGte("third_range", range: "[35,45)")
      .rangeLte("fourth_range", range: "[45,55)")
      .rangeAdjacent("fifth_range", range: "[55,65)")
      .execute()
  }

  func testOverlapsFilter() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?schedule=ov.%7B9:00,17:00%7D&select=*"
      """#
    }
    .register()

    _ =
      try await sut
      .from("users")
      .select()
      .overlaps("schedule", value: ["9:00", "17:00"])
      .execute()
  }

  func testMatchFilter() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?role=eq.admin&select=*&status=eq.active"
      """#
    }
    .register()

    _ =
      try await sut
      .from("users")
      .select()
      .match(["status": "active", "role": "admin"])
      .execute()
  }

  func testFilterEscapeHatch() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?created_at=gt.2023-01-01&select=*"
      """#
    }
    .register()

    _ =
      try await sut
      .from("users")
      .select()
      .filter("created_at", operator: "gt", value: "2023-01-01")
      .execute()
  }

  func testNeqFilter() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?select=*&status=neq.inactive"
      """#
    }
    .register()

    _ =
      try await sut
      .from("users")
      .select()
      .neq("status", value: "inactive")
      .execute()
  }

  func testGtFilter() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?age=gt.21&select=*"
      """#
    }
    .register()

    _ =
      try await sut
      .from("users")
      .select()
      .gt("age", value: 21)
      .execute()
  }

  func testLtFilter() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?age=lt.65&select=*"
      """#
    }
    .register()

    _ =
      try await sut
      .from("users")
      .select()
      .lt("age", value: 65)
      .execute()
  }

  func testLteFilter() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?age=lte.65&select=*"
      """#
    }
    .register()

    _ =
      try await sut
      .from("users")
      .select()
      .lte("age", value: 65)
      .execute()
  }

  func testLikeAllOfFilter() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?name=like(all).%7B%25test%25,%25user%25%7D&select=*"
      """#
    }
    .register()

    _ =
      try await sut
      .from("users")
      .select()
      .likeAllOf("name", patterns: ["%test%", "%user%"])
      .execute()
  }

  func testLikeAnyOfFilter() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?name=like(any).%7B%25test%25,%25user%25%7D&select=*"
      """#
    }
    .register()

    _ =
      try await sut
      .from("users")
      .select()
      .likeAnyOf("name", patterns: ["%test%", "%user%"])
      .execute()
  }

  func testILikeAllOfFilter() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?name=ilike(all).%7B%25TEST%25,%25USER%25%7D&select=*"
      """#
    }
    .register()

    _ =
      try await sut
      .from("users")
      .select()
      .iLikeAllOf("name", patterns: ["%TEST%", "%USER%"])
      .execute()
  }

  func testILikeAnyOfFilter() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?name=ilike(any).%7B%25TEST%25,%25USER%25%7D&select=*"
      """#
    }
    .register()

    _ =
      try await sut
      .from("users")
      .select()
      .iLikeAnyOf("name", patterns: ["%TEST%", "%USER%"])
      .execute()
  }

  func testFtsFilter() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?description=fts.programmer&select=*"
      """#
    }
    .register()

    _ =
      try await sut
      .from("users")
      .select()
      .fts("description", query: "programmer")
      .execute()
  }
}
