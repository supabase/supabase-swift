import Foundation
import PostgREST
import Testing

/// `openAPIDocument()` against a real PostgREST: the document of the default schema, the document
/// of a schema picked with `schema(_:)`, and `PGRST106` for a schema that is not exposed.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct PostgrestOpenAPIDocumentIntegrationTests {
  let client = try! PostgrestClient(
    configuration: .init(
      url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
      headers: [
        .apikey: DotEnv.supabaseSecretKey,
        .authorization: "Bearer \(DotEnv.supabaseSecretKey)",
      ]
    )
  )

  @Test
  func describesTheDefaultSchema() async throws {
    let document = try await client.openAPIDocument()

    #expect(document["swagger"] == .string("2.0"))
    #expect(document["info"]?.objectValue != nil)
    let paths = try #require(document["paths"]?.objectValue)
    #expect(paths["/todos"] != nil)
    #expect(paths["/places"] == nil)
  }

  @Test
  func describesTheSelectedSchema() async throws {
    let document = try await client.schema("personal").openAPIDocument()

    let paths = try #require(document["paths"]?.objectValue)
    #expect(paths["/places"] != nil)
    #expect(paths["/todos"] == nil)
  }

  @Test
  func rejectsASchemaThatIsNotExposed() async throws {
    let error = await #expect(throws: PostgrestError.self) {
      try await client.schema("not_exposed").openAPIDocument()
    }

    #expect(error?.code == "PGRST106")
  }
}
