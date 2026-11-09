//
//  PostgrestQueryBuilderTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/01/25.
//

import Foundation
import HTTPTypes
import PostgREST
import TestHelpers
import Testing

@Suite
struct PostgrestQueryBuilderTests {
  let fixture = try! PostgrestQueryFixture()
  var transport: RecordingTransport { fixture.transport }
  var url: URL { fixture.url }
  var sut: PostgrestClient { fixture.sut }

  private func sut(withPreferHeader value: String) throws -> PostgrestClient {
    var configuration = sut.configuration
    configuration.headers["Prefer"] = value
    return try PostgrestClient(configuration: configuration)
  }

  @Test
  func select() async throws {
    transport.stub(
      .get, url.appendingPathComponent("users"),
      data: Data(
        """
        [
          {
            "id": 1,
            "username": "supabase"
          }
        ]
        """.utf8
      )
    ) {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?select=*"
      """#
    }

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
    transport.stub(.get, url.appendingPathComponent("users")) {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?select=somecolumn"
      """#
    }

    try await sut
      .from("users")
      .select("some column")
      .execute()
  }

  @Test
  func selectWithQuoteInQuery() async throws {
    transport.stub(.get, url.appendingPathComponent("users")) {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?select=some%22column%22"
      """#
    }

    try await sut
      .from("users")
      .select(#"some "column""#)
      .execute()
  }

  @Test
  func selectWithCount() async throws {
    transport.stub(.head, url.appendingPathComponent("users"), headers: [.contentRange: "0-9/10"]) {
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
    transport.stub(.head, url.appendingPathComponent("users"), headers: [.contentRange: "0-9/10"]) {
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

    let count =
      try await sut(withPreferHeader: "existing=value")
      .from("users")
      .select(head: true, count: .exact)
      .execute()
      .count

    #expect(count == 10)
  }

  @Test
  func insert() async throws {
    transport.stub(.post, url.appendingPathComponent("users"), status: 201) {
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
    transport.stub(.post, url.appendingPathComponent("users"), status: 201) {
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

    try await sut
      .from("users")
      .insert([["a,b": 1]], returning: .minimal)
      .execute()
  }

  @Test
  func insertWithExistingPreferHeader() async throws {
    transport.stub(.post, url.appendingPathComponent("users"), status: 201) {
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

    try await sut(withPreferHeader: "existing=value")
      .from("users")
      .insert(User(id: 1, username: "supabase"), returning: .minimal)
      .execute()
  }

  @Test
  func update() async throws {
    transport.stub(.patch, url.appendingPathComponent("users"), status: 201) {
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

    try await sut(withPreferHeader: "existing=value")
      .from("users")
      .update(["username": "supabase2"], returning: .minimal, count: .planned)
      .eq("id", value: 1)
      .execute()
  }

  @Test
  func upsert() async throws {
    transport.stub(.post, url.appendingPathComponent("users"), status: 201) {
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

    try await sut(withPreferHeader: "existing=value")
      .from("users")
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
  func insertAndUpsertCannotBeFiltered() throws {
    let row = User(id: 1, username: "supabase")
    let users = sut.from("users")

    #expect(type(of: try users.insert(row)) == PostgrestTransformBuilder.self)
    #expect(type(of: try users.upsert(row)) == PostgrestTransformBuilder.self)
    #expect(type(of: try users.update(row)) == PostgrestFilterBuilder.self)
    #expect(type(of: users.delete()) == PostgrestFilterBuilder.self)
  }

  @Test
  func insertWithTransforms() async throws {
    transport.stub(
      .post, url.appendingPathComponent("users"), status: 201,
      data: Data(#"{"id":1,"username":"supabase"}"#.utf8)
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Accept: application/vnd.pgrst.object+json" \
      	--header "Content-Length: 30" \
      	--header "Content-Type: application/json" \
      	--header "Prefer: count=exact,return=representation" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"id\":1,\"username\":\"supabase\"}" \
      	"http://localhost:54321/rest/v1/users?limit=1&order=id.asc&select=id,username"
      """#
    }

    let _: User =
      try await sut
      .from("users")
      .insert(User(id: 1, username: "supabase"), count: .exact)
      .select("id,username")
      .order("id")
      .limit(1)
      .single()
      .execute()
      .value
  }

  @Test
  func upsertIgnoreDuplicates() async throws {
    transport.stub(.post, url.appendingPathComponent("users"), status: 201) {
      #"""
      curl \
      	--request POST \
      	--header "Accept: application/json" \
      	--header "Content-Length: 27" \
      	--header "Content-Type: application/json" \
      	--header "Prefer: resolution=ignore-duplicates" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"id\":1,\"username\":\"admin\"}" \
      	"http://localhost:54321/rest/v1/users"
      """#
    }

    try await sut
      .from("users")
      .upsert(User(id: 1, username: "admin"), ignoreDuplicates: true)
      .execute()
  }

  @Test
  func insertDefaultToNullFalseSendsMissingDefault() async throws {
    transport.stub(.post, url.appendingPathComponent("users"), status: 201) {
      #"""
      curl \
      	--request POST \
      	--header "Accept: application/json" \
      	--header "Content-Length: 27" \
      	--header "Content-Type: application/json" \
      	--header "Prefer: return=minimal,missing=default" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"id\":1,\"username\":\"admin\"}" \
      	"http://localhost:54321/rest/v1/users"
      """#
    }

    try await sut
      .from("users")
      .insert(User(id: 1, username: "admin"), returning: .minimal, defaultToNull: false)
      .execute()
  }

  @Test
  func insertDefaultToNullFalseComposesWithReturningAndCount() async throws {
    transport.stub(.post, url.appendingPathComponent("users"), status: 201) {
      #"""
      curl \
      	--request POST \
      	--header "Accept: application/json" \
      	--header "Content-Length: 60" \
      	--header "Content-Type: application/json" \
      	--header "Prefer: return=minimal,count=estimated,missing=default" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "[{\"id\":1,\"username\":\"admin\"},{\"id\":2,\"username\":\"supabase\"}]" \
      	"http://localhost:54321/rest/v1/users?columns=%22id%22,%22username%22"
      """#
    }

    try await sut
      .from("users")
      .insert(
        [
          User(id: 1, username: "admin"),
          User(id: 2, username: "supabase"),
        ],
        returning: .minimal,
        count: .estimated,
        defaultToNull: false
      )
      .execute()
  }

  @Test
  func upsertDefaultToNullFalseKeepsEveryOtherPreference() async throws {
    transport.stub(.post, url.appendingPathComponent("users"), status: 201) {
      #"""
      curl \
      	--request POST \
      	--header "Accept: application/json" \
      	--header "Content-Length: 60" \
      	--header "Content-Type: application/json" \
      	--header "Prefer: existing=value,resolution=merge-duplicates,return=minimal,count=estimated,missing=default" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "[{\"id\":1,\"username\":\"admin\"},{\"id\":2,\"username\":\"supabase\"}]" \
      	"http://localhost:54321/rest/v1/users?columns=%22id%22,%22username%22&on_conflict=username"
      """#
    }

    try await sut(withPreferHeader: "existing=value")
      .from("users")
      .upsert(
        [
          User(id: 1, username: "admin"),
          User(id: 2, username: "supabase"),
        ],
        onConflict: "username",
        returning: .minimal,
        count: .estimated,
        defaultToNull: false
      )
      .execute()
  }

  @Test
  func upsertDefaultToNullFalseComposesWithIgnoreDuplicates() async throws {
    transport.stub(.post, url.appendingPathComponent("users"), status: 201) {
      #"""
      curl \
      	--request POST \
      	--header "Accept: application/json" \
      	--header "Content-Length: 27" \
      	--header "Content-Type: application/json" \
      	--header "Prefer: resolution=ignore-duplicates,missing=default" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"id\":1,\"username\":\"admin\"}" \
      	"http://localhost:54321/rest/v1/users"
      """#
    }

    try await sut
      .from("users")
      .upsert(
        User(id: 1, username: "admin"),
        ignoreDuplicates: true,
        defaultToNull: false
      )
      .execute()
  }

  @Test
  func delete() async throws {
    transport.stub(.delete, url.appendingPathComponent("users"), status: 204) {
      #"""
      curl \
      	--request DELETE \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "Prefer: existing=value,count=estimated" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/users?username=eq.supabase"
      """#
    }

    try await sut(withPreferHeader: "existing=value")
      .from("users")
      .delete(count: .estimated)
      .eq("username", value: "supabase")
      .execute()
  }
}
