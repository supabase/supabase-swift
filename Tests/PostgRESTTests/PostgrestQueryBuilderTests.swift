//
//  PostgrestQueryBuilderTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/01/25.
//

import Foundation
import Mocker
import PostgREST
import TestHelpers
import Testing

extension PostgrestMockerTests {
  struct PostgrestQueryBuilderTests {
    let fixture = PostgrestQueryFixture()
    var url: URL { fixture.url }
    var sut: PostgrestClient { fixture.sut }

    @Test
    func setAuth() {
      #expect(sut.configuration.headers["Authorization"] == nil)
      sut.setAuth("token")
      #expect(sut.configuration.headers["Authorization"] == "Bearer token")

      sut.setAuth(nil)
      #expect(sut.configuration.headers["Authorization"] == nil)
    }

    @Test
    func select() async throws {
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

      #expect(users[0].id == 1)
      #expect(users[0].username == "supabase")
    }

    @Test
    func selectWithWhitespaceInQuery() async throws {
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

    @Test
    func selectWithQuoteInQuery() async throws {
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

    @Test
    func selectWithCount() async throws {
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

      #expect(count == 10)
    }

    @Test
    func selectWithExistingPreferHeader() async throws {
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
        	--header "Prefer: existing=value,count=exact" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?select=*"
        """#
      }
      .register()

      let count =
        try await sut
        .from("users")
        .setHeader(name: "Prefer", value: "existing=value")
        .select(head: true, count: .exact)
        .execute()
        .count

      #expect(count == 10)
    }

    @Test
    func insert() async throws {
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
        	"http://localhost:54321/rest/v1/users?columns=%22id%22,%22username%22"
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

    @Test
    func insertQuotesColumnNameContainingReservedCharacter() async throws {
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
        	--header "Content-Length: 11" \
        	--header "Content-Type: application/json" \
        	--header "Prefer: return=minimal" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "[{\"a,b\":1}]" \
        	"http://localhost:54321/rest/v1/users?columns=%22a,b%22"
        """#
      }
      .register()

      try await sut
        .from("users")
        .insert([["a,b": 1]], returning: .minimal)
        .execute()
    }

    @Test
    func insertWithExistingPreferHeader() async throws {
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

    @Test
    func update() async throws {
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

    @Test
    func upsert() async throws {
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
        	"http://localhost:54321/rest/v1/users?columns=%22id%22,%22username%22&on_conflict=username"
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

    @Test
    func upsertIgnoreDuplicates() async throws {
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

    @Test
    func delete() async throws {
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
}
