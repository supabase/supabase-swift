//
//  SupabaseClientTypedSchemaTests.swift
//  Supabase
//
//  Created by Ranbir Singh on 19/09/26.
//

import Foundation
import HTTPTypes
import TestHelpers
import Testing

@_spi(Experimental) @testable import Supabase

@Suite
struct SupabaseClientTypedSchemaTests {
  enum PrivateSchema: _PostgrestSchema {
    static let name = "private"
  }

  struct Secret: _PostgrestRelation {
    typealias Schema = PrivateSchema
    static let relationName = "secrets"
    static let selectString = "*"

    var id: Int

    struct Columns: Sendable {
      let id = _PostgrestColumn<Secret, Int>("id")
    }

    static let columns = Columns()
  }

  private let transport = RecordingTransport { _, _ in
    (
      HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]),
      Data("[]".utf8)
    )
  }

  private func makeClient(schema: String? = nil) throws -> SupabaseClient {
    try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        database: SupabaseClient.Configuration.Database(schema: schema),
        auth: SupabaseClient.Configuration.Auth(
          storage: InMemoryAuthStorage(),
          autoRefresh: .manual
        ),
        global: SupabaseClient.Configuration.Global(http: .init(transport: transport))
      )
    )
  }

  private func sentProfile() throws -> String? {
    try #require(transport.requests.last).head.headerFields[HTTPField.Name("Accept-Profile")!]
  }

  @Test
  func fromQueriesTheRelationInItsOwnSchema() async throws {
    let supabase = try makeClient()

    _ = try await supabase.from(Secret.self).select().execute()

    #expect(try sentProfile() == "private")
  }

  @Test
  func theScopeQueriesItsSchema() async throws {
    let supabase = try makeClient()

    _ = try await supabase.schema(PrivateSchema.self).from(Secret.self).select().execute()

    #expect(try sentProfile() == "private")
  }

  @Test
  func aSchemaInTheDatabaseConfigurationWins() async throws {
    let supabase = try makeClient(schema: "public")

    _ = try await supabase.from(Secret.self).select().execute()

    #expect(try sentProfile() == "public")
  }
}
