//
//  AuthAdminOAuthTests.swift
//
//
//  Created by Guilherme Souza on 02/10/25.
//

import ConcurrencyExtras
import CustomDump
import InlineSnapshotTesting
import Mocker
import TestHelpers
import XCTest

@testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class AuthAdminOAuthTests: XCTestCase {
  var sut: AuthClient!
  var storage: InMemoryLocalStorage!

  #if !os(Windows) && !os(Linux) && !os(Android)
    override func invokeTest() {
      withMainSerialExecutor {
        super.invokeTest()
      }
    }
  #endif

  override func setUp() {
    super.setUp()
    storage = InMemoryLocalStorage()
  }

  override func tearDown() {
    super.tearDown()

    Mocker.removeAll()

    let completion = { [weak sut] in
      XCTAssertNil(sut, "sut should not leak")
    }

    defer { completion() }

    sut = nil
    storage = nil
  }

  private func makeSUT() -> AuthClient {
    let sessionConfiguration = URLSessionConfiguration.default
    sessionConfiguration.protocolClasses = [MockingURLProtocol.self]
    let session = URLSession(configuration: sessionConfiguration)

    let encoder = AuthClient.Configuration.jsonEncoder
    encoder.outputFormatting = [.sortedKeys]

    let configuration = AuthClient.Configuration(
      url: clientURL,
      headers: [
        "apikey": "supabase.anon.key",
        "Authorization": "Bearer supabase.service_role.key"
      ],
      localStorage: storage,
      logger: nil,
      encoder: encoder,
      fetch: { request in
        try await session.data(for: request)
      }
    )

    return AuthClient(configuration: configuration)
  }

  func testListOAuthClients() async throws {
    let responseData = """
      {
        "clients": [
          {
            "client_id": "test-client-id",
            "client_name": "Test Client",
            "client_type": "confidential",
            "token_endpoint_auth_method": "client_secret_post",
            "registration_type": "manual",
            "redirect_uris": ["https://example.com/callback"],
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "created_at": "2024-01-01T00:00:00.000Z",
            "updated_at": "2024-01-01T00:00:00.000Z"
          }
        ],
        "aud": "authenticated"
      }
      """.data(using: .utf8)!

    Mock(
      url: clientURL.appendingPathComponent("admin/oauth/clients"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: responseData],
      additionalHeaders: [
        "x-total-count": "1",
        "link": "<https://example.com?page=1>; rel=\"last\""
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Authorization: Bearer supabase.service_role.key" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.anon.key" \
      	"http://localhost:54321/auth/v1/admin/oauth/clients?page=&per_page="
      """#
    }.register()

    sut = makeSUT()

    let response = try await sut.admin.oauth.listClients()

    XCTAssertEqual(response.clients.count, 1)
    XCTAssertEqual(response.clients[0].clientId, "test-client-id")
    XCTAssertEqual(response.clients[0].clientName, "Test Client")
    XCTAssertEqual(response.aud, "authenticated")
    XCTAssertEqual(response.total, 1)
  }

  func testCreateOAuthClient() async throws {
    let responseData = """
      {
        "client_id": "new-client-id",
        "client_name": "New Client",
        "client_secret": "secret123",
        "client_type": "confidential",
        "token_endpoint_auth_method": "client_secret_post",
        "registration_type": "manual",
        "redirect_uris": ["https://example.com/callback"],
        "grant_types": ["authorization_code", "refresh_token"],
        "response_types": ["code"],
        "created_at": "2024-01-01T00:00:00.000Z",
        "updated_at": "2024-01-01T00:00:00.000Z"
      }
      """.data(using: .utf8)!

    Mock(
      url: clientURL.appendingPathComponent("admin/oauth/clients"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: responseData]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer supabase.service_role.key" \
      	--header "Content-Length: 80" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.anon.key" \
      	--data "{\"client_name\":\"New Client\",\"redirect_uris\":[\"https:\/\/example.com\/callback\"]}" \
      	"http://localhost:54321/auth/v1/admin/oauth/clients"
      """#
    }.register()

    sut = makeSUT()

    let params = CreateOAuthClientParams(
      clientName: "New Client",
      redirectUris: ["https://example.com/callback"]
    )

    let client = try await sut.admin.oauth.createClient(params: params)

    XCTAssertEqual(client.clientId, "new-client-id")
    XCTAssertEqual(client.clientName, "New Client")
    XCTAssertEqual(client.clientSecret, "secret123")
  }

  func testGetOAuthClient() async throws {
    let responseData = """
      {
        "client_id": "test-client-id",
        "client_name": "Test Client",
        "client_type": "confidential",
        "token_endpoint_auth_method": "client_secret_post",
        "registration_type": "manual",
        "redirect_uris": ["https://example.com/callback"],
        "grant_types": ["authorization_code", "refresh_token"],
        "response_types": ["code"],
        "created_at": "2024-01-01T00:00:00.000Z",
        "updated_at": "2024-01-01T00:00:00.000Z"
      }
      """.data(using: .utf8)!

    Mock(
      url: clientURL.appendingPathComponent("admin/oauth/clients/test-client-id"),
      statusCode: 200,
      data: [.get: responseData]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Authorization: Bearer supabase.service_role.key" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.anon.key" \
      	"http://localhost:54321/auth/v1/admin/oauth/clients/test-client-id"
      """#
    }.register()

    sut = makeSUT()

    let client = try await sut.admin.oauth.getClient(clientId: "test-client-id")

    XCTAssertEqual(client.clientId, "test-client-id")
    XCTAssertEqual(client.clientName, "Test Client")
  }

  func testDeleteOAuthClient() async throws {
    let responseData = """
      {
        "client_id": "test-client-id",
        "client_name": "Test Client",
        "client_type": "confidential",
        "token_endpoint_auth_method": "client_secret_post",
        "registration_type": "manual",
        "redirect_uris": ["https://example.com/callback"],
        "grant_types": ["authorization_code", "refresh_token"],
        "response_types": ["code"],
        "created_at": "2024-01-01T00:00:00.000Z",
        "updated_at": "2024-01-01T00:00:00.000Z"
      }
      """.data(using: .utf8)!

    Mock(
      url: clientURL.appendingPathComponent("admin/oauth/clients/test-client-id"),
      statusCode: 200,
      data: [.delete: responseData]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request DELETE \
      	--header "Authorization: Bearer supabase.service_role.key" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.anon.key" \
      	"http://localhost:54321/auth/v1/admin/oauth/clients/test-client-id"
      """#
    }.register()

    sut = makeSUT()

    let client = try await sut.admin.oauth.deleteClient(clientId: "test-client-id")

    XCTAssertEqual(client.clientId, "test-client-id")
  }

  func testRegenerateOAuthClientSecret() async throws {
    let responseData = """
      {
        "client_id": "test-client-id",
        "client_name": "Test Client",
        "client_secret": "new-secret456",
        "client_type": "confidential",
        "token_endpoint_auth_method": "client_secret_post",
        "registration_type": "manual",
        "redirect_uris": ["https://example.com/callback"],
        "grant_types": ["authorization_code", "refresh_token"],
        "response_types": ["code"],
        "created_at": "2024-01-01T00:00:00.000Z",
        "updated_at": "2024-01-01T00:00:00.000Z"
      }
      """.data(using: .utf8)!

    Mock(
      url: clientURL.appendingPathComponent("admin/oauth/clients/test-client-id/regenerate_secret"),
      statusCode: 200,
      data: [.post: responseData]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer supabase.service_role.key" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.anon.key" \
      	"http://localhost:54321/auth/v1/admin/oauth/clients/test-client-id/regenerate_secret"
      """#
    }.register()

    sut = makeSUT()

    let client = try await sut.admin.oauth.regenerateClientSecret(clientId: "test-client-id")

    XCTAssertEqual(client.clientId, "test-client-id")
    XCTAssertEqual(client.clientSecret, "new-secret456")
  }
}
