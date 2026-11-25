import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@testable import PostgREST

@Suite
struct PostgrestOpenAPIDocumentTests {
  let url = URL(string: "https://example.supabase.co/rest/v1")!
  let rootURL = URL(string: "https://example.supabase.co/rest/v1/")!

  func makeClient(transport: RecordingTransport, schema: String? = nil) throws -> PostgrestClient {
    try PostgrestClient(
      configuration: .init(
        url: url,
        schema: schema,
        headers: [.xClientInfo: "postgrest-swift/x.y.z", .apikey: "anon-key"],
        http: .init(transport: transport),
        retryEnabled: false
      )
    )
  }

  @Test
  func requestsTheRootWithTheOpenAPIMediaType() async throws {
    let transport = RecordingTransport()
    transport.stub(.get, rootURL, data: Data(#"{"swagger":"2.0","info":{},"paths":{}}"#.utf8))

    _ = try await makeClient(transport: transport).openAPIDocument()

    try transport.assertFirstRequestSnapshot(.get, rootURL) {
      #"""
      curl \
      	--header "Accept: application/openapi+json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/x.y.z" \
      	--header "apikey: anon-key" \
      	"https://example.supabase.co/rest/v1/"
      """#
    }
  }

  @Test
  func sendsTheSelectedSchemaAsAcceptProfile() async throws {
    let transport = RecordingTransport()
    transport.stub(.get, rootURL, data: Data(#"{"swagger":"2.0","info":{},"paths":{}}"#.utf8))

    _ = try await makeClient(transport: transport).schema("billing").openAPIDocument()

    try transport.assertFirstRequestSnapshot(.get, rootURL) {
      #"""
      curl \
      	--header "Accept: application/openapi+json" \
      	--header "Accept-Profile: billing" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/x.y.z" \
      	--header "apikey: anon-key" \
      	"https://example.supabase.co/rest/v1/"
      """#
    }
  }

  @Test
  func decodesTheDocumentAsRawJSON() async throws {
    let transport = RecordingTransport()
    transport.stub(
      .get, rootURL,
      data: Data(
        #"""
        {
          "swagger": "2.0",
          "info": {"title": "standard public schema", "version": "12.2.3"},
          "host": "0.0.0.0:3000",
          "paths": {
            "/": {"get": {"tags": ["Introspection"]}},
            "/todos": {"get": {"tags": ["todos"]}}
          },
          "definitions": {"todos": {"required": ["id"], "type": "object"}},
          "x-unknown": [1, 2.5, null]
        }
        """#.utf8))

    let document = try await makeClient(transport: transport).openAPIDocument()

    #expect(document["swagger"] == .string("2.0"))
    #expect(document["info"]?.objectValue?["version"] == .string("12.2.3"))
    #expect(document["paths"]?.objectValue.map { Set($0.keys) } == ["/", "/todos"])
    #expect(document["definitions"]?.objectValue?["todos"] != nil)
    #expect(document["x-unknown"]?.arrayValue?.count == 3)
  }

  @Test
  func acceptsADocumentWithOnlyTheRequiredFields() async throws {
    let transport = RecordingTransport()
    transport.stub(
      .get, rootURL,
      data: Data(#"{"swagger":"2.0","info":{"title":"custom"},"paths":{}}"#.utf8))

    let document = try await makeClient(transport: transport).openAPIDocument()

    #expect(
      document == [
        "swagger": .string("2.0"),
        "info": .object(["title": .string("custom")]),
        "paths": .object([:]),
      ])
  }

  @Test
  func throwsTheServerErrorForAnUnexposedSchema() async throws {
    let transport = RecordingTransport()
    transport.stub(
      .get, rootURL, status: 406,
      data: Data(
        #"""
        {"code":"PGRST106","details":null,"hint":"Only the following schemas are exposed: public",\#
        "message":"Invalid schema: billing"}
        """#.utf8))

    let error = await #expect(throws: PostgrestError.self) {
      try await makeClient(transport: transport).schema("billing").openAPIDocument()
    }

    #expect(error?.kind == .server)
    #expect(error?.code == "PGRST106")
    #expect(error?.response?.status == 406)
  }

  @Test
  func throwsTheServerErrorWhenOpenAPIOutputIsDisabled() async throws {
    let transport = RecordingTransport()
    transport.stub(.get, rootURL, status: 404, data: Data())

    let error = await #expect(throws: PostgrestError.self) {
      try await makeClient(transport: transport).openAPIDocument()
    }

    #expect(error?.kind == .server)
    #expect(error?.response?.status == 404)
  }

  @Test
  func throwsADecodingErrorWhenTheBodyIsNotJSON() async throws {
    let transport = RecordingTransport()
    transport.stub(.get, rootURL, data: Data("not json".utf8))

    let error = await #expect(throws: PostgrestError.self) {
      try await makeClient(transport: transport).openAPIDocument()
    }

    #expect(error?.kind == .decoding)
  }
}
