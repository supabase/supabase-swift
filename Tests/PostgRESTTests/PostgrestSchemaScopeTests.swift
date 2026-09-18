import Foundation
import Testing

@testable import PostgREST

@Suite
struct PostgrestSchemaScopeTests {
  enum PrivateSchema: PostgrestSchema {
    static let name = "private"
  }

  struct Secret: PostgrestRelation {
    typealias Schema = PrivateSchema
    static let relationName = "secrets"
    static let selectString = "*"

    var id: Int

    struct Columns: Sendable {
      let id = PostgrestColumn<Secret, Int>("id")
    }

    static let columns = Columns()
  }

  struct Todo: PostgrestRelation {
    static let relationName = "todos"
    static let selectString = "*"

    var id: Int

    struct Columns: Sendable {
      let id = PostgrestColumn<Todo, Int>("id")
    }

    static let columns = Columns()
  }

  @Test
  func schemaStringComesFromTheDeclaredType() {
    #expect(Secret.schema == "private")
    #expect(Todo.schema == "public")
  }

  @Test
  func fromQueriesTheRelationInItsOwnSchema() async throws {
    let capture = QueryCapture()

    _ = try await capture.client.from(Secret.self).select().execute()

    #expect(capture.header("Accept-Profile") == "private")
  }

  @Test
  func fromSendsNoProfileForARelationInTheDefaultSchema() async throws {
    let capture = QueryCapture()

    _ = try await capture.client.from(Todo.self).select().execute()

    #expect(capture.header("Accept-Profile") == nil)
  }

  @Test
  func theScopeQueriesItsSchema() async throws {
    let capture = QueryCapture()

    _ = try await capture.client.schema(PrivateSchema.self).from(Secret.self).select().execute()

    #expect(capture.header("Accept-Profile") == "private")
    #expect(capture.path?.hasSuffix("/secrets") == true)
  }

  @Test
  func theScopeStillTakesARelationName() async throws {
    let capture = QueryCapture()

    _ = try await capture.client.schema(PrivateSchema.self).from("secrets").select().execute()

    #expect(capture.header("Accept-Profile") == "private")
    #expect(capture.path?.hasSuffix("/secrets") == true)
  }

  @Test
  func aSchemaSetOnTheClientWins() async throws {
    let capture = QueryCapture()

    _ = try await capture.client.schema("other").from(Secret.self).select().execute()

    #expect(capture.header("Accept-Profile") == "other")
  }
}
