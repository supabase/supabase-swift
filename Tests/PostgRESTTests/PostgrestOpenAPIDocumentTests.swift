import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@testable import PostgREST

@Suite
struct PostgrestOpenAPIDocumentTests {
  let rootURL = URL(string: "https://example.supabase.co/rest/v1/")!
  let transport = RecordingTransport()

  /// A client whose `GET /` answers with `status` and `body`.
  func makeClient(
    status: HTTPResponse.Status = .ok,
    body: String = #"{"swagger":"2.0","info":{},"paths":{}}"#
  ) throws -> PostgrestClient {
    transport.stub(.get, rootURL, status: status, data: Data(body.utf8))
    return try PostgrestClient(
      configuration: .init(
        url: URL(string: "https://example.supabase.co/rest/v1")!,
        headers: [.xClientInfo: "postgrest-swift/x.y.z", .apikey: "anon-key"],
        http: .init(transport: transport),
        retryEnabled: false
      )
    )
  }

  @Test
  func requestsTheRootWithTheOpenAPIMediaType() async throws {
    _ = try await makeClient().openAPIDocument()

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
    _ = try await makeClient().schema("billing").openAPIDocument()

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
    let document = try await makeClient(
      body: #"""
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
        """#
    ).openAPIDocument()

    #expect(document["swagger"] == .string("2.0"))
    #expect(document["info"]?.objectValue?["version"] == .string("12.2.3"))
    #expect(document["paths"]?.objectValue.map { Set($0.keys) } == ["/", "/todos"])
    #expect(document["definitions"]?.objectValue?["todos"] != nil)
    #expect(document["x-unknown"]?.arrayValue?.count == 3)
  }

  @Test
  func throwsTheServerErrorForAnUnexposedSchema() async throws {
    let client = try makeClient(
      status: .notAcceptable,
      body: #"""
        {"code":"PGRST106","details":null,"hint":"Only the following schemas are exposed: public",\#
        "message":"Invalid schema: billing"}
        """#
    )

    let error = await #expect(throws: PostgrestError.self) {
      try await client.schema("billing").openAPIDocument()
    }

    #expect(error?.kind == .server)
    #expect(error?.code == "PGRST106")
    #expect(error?.response?.status == 406)
  }

  @Test
  func throwsTheServerErrorWhenOpenAPIOutputIsDisabled() async throws {
    let client = try makeClient(status: .notFound, body: "")

    let error = await #expect(throws: PostgrestError.self) {
      try await client.openAPIDocument()
    }

    #expect(error?.kind == .server)
    #expect(error?.response?.status == 404)
  }

  @Test
  func throwsADecodingErrorWhenTheBodyIsNotJSON() async throws {
    let client = try makeClient(body: "not json")

    let error = await #expect(throws: PostgrestError.self) {
      try await client.openAPIDocument()
    }

    #expect(error?.kind == .decoding)
  }
}
