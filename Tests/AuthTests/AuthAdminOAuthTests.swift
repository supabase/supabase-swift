//
//  AuthAdminOAuthTests.swift
//
//
//  Created by Guilherme Souza on 02/10/25.
//

import ConcurrencyExtras
import CustomDump
import Foundation
import InlineSnapshotTesting
import Mocker
import TestHelpers
import Testing

@testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Shared serialization boundary for the Mocker-backed AuthTests suites: Mocker's mock registry is
/// process-global, and these suites stub overlapping URLs, so running them concurrently would let
/// one suite's stub satisfy another's request. `.serialized` on a suite applies recursively to its
/// nested suites, so nesting all of them under this empty namespace serializes them against each
/// other within this target. Each nested suite also carries `.mockerSerialized` (see
/// `TestHelpers/MockerSerialization.swift`) to extend that guarantee across test *targets* too.
@Suite(.serialized)
enum AuthMockerTests {}

extension AuthMockerTests {
  @Suite(.mockerSerialized)
  struct AuthAdminOAuthTests {
    let clientId = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!

    let storage = InMemoryLocalStorage()

    private func makeSUT() -> AuthClient {
      let sessionConfiguration = URLSessionConfiguration.default
      sessionConfiguration.protocolClasses = [MockingURLProtocol.self]
      let session = URLSession(configuration: sessionConfiguration)

      let encoder = AuthClient.Configuration.jsonEncoder
      encoder.outputFormatting = [.sortedKeys]

      let configuration = AuthClient.Configuration(
        url: clientURL,
        headers: [
          "apikey": "supabase.publishable.key",
          "Authorization": "Bearer supabase.secret.key",
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

    @Test
    func listOAuthClients() async throws {
      let responseData = """
        {
          "clients": [
            {
              "client_id": "\(clientId)",
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
          "link": "<https://example.com?page=1>; rel=\"last\"",
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Authorization: Bearer supabase.secret.key" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: supabase.publishable.key" \
        	"http://localhost:54321/auth/v1/admin/oauth/clients?page=&per_page="
        """#
      }
      .register()

      let sut = makeSUT()

      let response = try await sut.admin.oauth.listClients()

      #expect(response.clients.count == 1)
      #expect(response.clients[0].clientId == clientId)
      #expect(response.clients[0].clientName == "Test Client")
      #expect(response.aud == "authenticated")
      #expect(response.total == 1)
    }

    @Test
    func updateOAuthClient() async throws {
      let responseData = """
        {
          "client_id": "\(clientId)",
          "client_name": "Update Client name",
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
        url: clientURL.appendingPathComponent("admin/oauth/clients/\(clientId)"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.put: responseData]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request PUT \
        	--header "Authorization: Bearer supabase.secret.key" \
        	--header "Content-Length: 141" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: supabase.publishable.key" \
        	--data "{\"client_name\":\"Update Client name\",\"grant_types\":[\"authorization_code\",\"refresh_token\"],\"redirect_uris\":[\"https:\/\/example.com\/callback\"]}" \
        	"http://localhost:54321/auth/v1/admin/oauth/clients/E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
        """#
      }
      .register()

      let sut = makeSUT()

      let client = try await sut.admin.oauth.updateClient(
        clientId: clientId,
        params: UpdateOAuthClientParams(
          clientName: "Update Client name",
          redirectUris: ["https://example.com/callback"],
          grantTypes: [.authorizationCode, .refreshToken]
        )
      )

      #expect(client.clientId == clientId)
      #expect(client.clientName == "Update Client name")
      #expect(client.clientSecret == "secret123")
    }

    @Test
    func createOAuthClient() async throws {
      let responseData = """
        {
          "client_id": "\(clientId)",
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
        	--header "Authorization: Bearer supabase.secret.key" \
        	--header "Content-Length: 80" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: supabase.publishable.key" \
        	--data "{\"client_name\":\"New Client\",\"redirect_uris\":[\"https:\/\/example.com\/callback\"]}" \
        	"http://localhost:54321/auth/v1/admin/oauth/clients"
        """#
      }
      .register()

      let sut = makeSUT()

      let params = CreateOAuthClientParams(
        clientName: "New Client",
        redirectUris: ["https://example.com/callback"]
      )

      let client = try await sut.admin.oauth.createClient(params: params)

      #expect(client.clientId == clientId)
      #expect(client.clientName == "New Client")
      #expect(client.clientSecret == "secret123")
    }

    @Test
    func getOAuthClient() async throws {
      let responseData = """
        {
          "client_id": "\(clientId)",
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
        url: clientURL.appendingPathComponent("admin/oauth/clients/\(clientId)"),
        statusCode: 200,
        data: [.get: responseData]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Authorization: Bearer supabase.secret.key" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: supabase.publishable.key" \
        	"http://localhost:54321/auth/v1/admin/oauth/clients/E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
        """#
      }
      .register()

      let sut = makeSUT()

      let client = try await sut.admin.oauth.getClient(clientId: clientId)

      #expect(client.clientId == clientId)
      #expect(client.clientName == "Test Client")
    }

    @Test
    func deleteOAuthClient() async throws {
      Mock(
        url: clientURL.appendingPathComponent("admin/oauth/clients/\(clientId)"),
        statusCode: 204,
        data: [.delete: Data()]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request DELETE \
        	--header "Authorization: Bearer supabase.secret.key" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: supabase.publishable.key" \
        	"http://localhost:54321/auth/v1/admin/oauth/clients/E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
        """#
      }
      .register()

      let sut = makeSUT()

      try await sut.admin.oauth.deleteClient(clientId: clientId)
    }

    @Test
    func regenerateOAuthClientSecret() async throws {
      let responseData = """
        {
          "client_id": "\(clientId)",
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
        url: clientURL.appendingPathComponent("admin/oauth/clients/\(clientId)/regenerate_secret"),
        statusCode: 200,
        data: [.post: responseData]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Authorization: Bearer supabase.secret.key" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: supabase.publishable.key" \
        	"http://localhost:54321/auth/v1/admin/oauth/clients/E621E1F8-C36C-495A-93FC-0C247A3E6E5F/regenerate_secret"
        """#
      }
      .register()

      let sut = makeSUT()

      let client = try await sut.admin.oauth.regenerateClientSecret(clientId: clientId)

      #expect(client.clientId == clientId)
      #expect(client.clientSecret == "new-secret456")
    }
  }
}
