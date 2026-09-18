//
//  SupabaseClientTypedSchemaTests.swift
//  Supabase
//
//  Created by Ranbir Singh on 19/09/26.
//

import ConcurrencyExtras
import Foundation
import Testing

@testable import Supabase

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

private final class TypedSchemaCapturingProtocol: URLProtocol {
  private static let storage = LockIsolated<URLRequest?>(nil)
  static var capturedRequest: URLRequest? {
    get { storage.value }
    set { storage.setValue(newValue) }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.capturedRequest = request
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data("[]".utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Suite(.serialized)
struct SupabaseClientTypedSchemaTests {
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

  private func makeClient(schema: String? = nil) -> SupabaseClient {
    TypedSchemaCapturingProtocol.capturedRequest = nil
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [TypedSchemaCapturingProtocol.self]
    return SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        db: SupabaseClientOptions.DatabaseOptions(schema: schema),
        auth: SupabaseClientOptions.AuthOptions(
          storage: AuthLocalStorageMock(),
          automaticallyRefreshesToken: false
        ),
        global: SupabaseClientOptions.GlobalOptions(
          http: .init(
            transport: URLSessionTransport(session: URLSession(configuration: configuration))
          )
        )
      )
    )
  }

  private func sentProfile() throws -> String? {
    try #require(TypedSchemaCapturingProtocol.capturedRequest)
      .value(forHTTPHeaderField: "Accept-Profile")
  }

  @Test
  func fromQueriesTheRelationInItsOwnSchema() async throws {
    let supabase = makeClient()

    _ = try await supabase.from(Secret.self).select().execute()

    #expect(try sentProfile() == "private")
  }

  @Test
  func theScopeQueriesItsSchema() async throws {
    let supabase = makeClient()

    _ = try await supabase.schema(PrivateSchema.self).from(Secret.self).select().execute()

    #expect(try sentProfile() == "private")
  }

  @Test
  func aSchemaInTheDatabaseOptionsWins() async throws {
    let supabase = makeClient(schema: "public")

    _ = try await supabase.from(Secret.self).select().execute()

    #expect(try sentProfile() == "public")
  }
}
