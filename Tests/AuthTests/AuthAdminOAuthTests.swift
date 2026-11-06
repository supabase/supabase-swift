//
//  AuthAdminOAuthTests.swift
//
//
//  Created by Guilherme Souza on 02/10/25.
//

import ConcurrencyExtras
import CustomDump
import Foundation
import HTTPTypes
import HTTPTypesFoundation
import Helpers
import InlineSnapshotTesting
import TestHelpers
import Testing

@testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct AuthAdminOAuthTests {
  let clientID = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
  let transport = RecordingTransport()

  @Test
  func listOAuthClients() async throws {
    let responseData = """
      {
        "clients": [
          {
            "client_id": "\(clientID)",
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

    transport.stub(.get, "admin/oauth/clients") { request, _ in
      #if !os(Linux) && !os(Android)
        assertInlineSnapshot(of: URLRequest(httpRequest: request)!, as: ._curl) {
          #"""
          curl \
          	--header "Authorization: Bearer supabase.secret.key" \
          	--header "X-Client-Info: auth-swift/0.0.0" \
          	--header "X-Supabase-Api-Version: 2024-01-01" \
          	--header "apikey: supabase.secret.key" \
          	"http://localhost:54321/auth/v1/admin/oauth/clients"
          """#
        }
      #endif
      return (
        HTTPResponse(
          status: .ok,
          headerFields: [
            .contentType: "application/json",
            HTTPField.Name("x-total-count")!: "1",
            .link: "<https://example.com?page=1>; rel=\"last\"",
          ]),
        responseData
      )
    }

    let sut = AuthAdminClient.testing(http: transport)

    let response = try await sut.oauth.listClients()

    #expect(response.clients.count == 1)
    #expect(response.clients[0].clientID == clientID)
    #expect(response.clients[0].clientName == "Test Client")
    #expect(response.audience == "authenticated")
    #expect(response.total == 1)
  }

  @Test
  func updateOAuthClient() async throws {
    let responseData = """
      {
        "client_id": "\(clientID)",
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

    transport.stub(.put, "admin/oauth/clients/\(clientID)", data: responseData) {
      #"""
      curl \
      	--request PUT \
      	--header "Authorization: Bearer supabase.secret.key" \
      	--header "Content-Length: 141" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.secret.key" \
      	--data "{\"client_name\":\"Update Client name\",\"grant_types\":[\"authorization_code\",\"refresh_token\"],\"redirect_uris\":[\"https:\/\/example.com\/callback\"]}" \
      	"http://localhost:54321/auth/v1/admin/oauth/clients/E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
      """#
    }

    let sut = AuthAdminClient.testing(http: transport)

    let client = try await sut.oauth.updateClient(
      id: clientID,
      params: UpdateOAuthClientParams(
        clientName: "Update Client name",
        redirectURIs: ["https://example.com/callback"],
        grantTypes: [.authorizationCode, .refreshToken]
      )
    )

    #expect(client.clientID == clientID)
    #expect(client.clientName == "Update Client name")
    #expect(client.clientSecret == "secret123")
  }

  @Test
  func createOAuthClient() async throws {
    let responseData = """
      {
        "client_id": "\(clientID)",
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

    transport.stub(.post, "admin/oauth/clients", data: responseData) {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer supabase.secret.key" \
      	--header "Content-Length: 80" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.secret.key" \
      	--data "{\"client_name\":\"New Client\",\"redirect_uris\":[\"https:\/\/example.com\/callback\"]}" \
      	"http://localhost:54321/auth/v1/admin/oauth/clients"
      """#
    }

    let sut = AuthAdminClient.testing(http: transport)

    let params = CreateOAuthClientParams(
      clientName: "New Client",
      redirectURIs: ["https://example.com/callback"]
    )

    let client = try await sut.oauth.createClient(params: params)

    #expect(client.clientID == clientID)
    #expect(client.clientName == "New Client")
    #expect(client.clientSecret == "secret123")
  }

  @Test
  func getOAuthClient() async throws {
    let responseData = """
      {
        "client_id": "\(clientID)",
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

    transport.stub(.get, "admin/oauth/clients/\(clientID)", data: responseData) {
      #"""
      curl \
      	--header "Authorization: Bearer supabase.secret.key" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.secret.key" \
      	"http://localhost:54321/auth/v1/admin/oauth/clients/E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
      """#
    }

    let sut = AuthAdminClient.testing(http: transport)

    let client = try await sut.oauth.client(id: clientID)

    #expect(client.clientID == clientID)
    #expect(client.clientName == "Test Client")
    #expect(client.redirectURIs == ["https://example.com/callback"])
    #expect(client.grantTypes == [.authorizationCode, .refreshToken])
    #expect(client.responseTypes == [.code])
  }

  @Test
  func getOAuthClientWithoutClientName() async throws {
    let responseData = """
      {
        "client_id": "\(clientID)",
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

    transport.stub(.get, "admin/oauth/clients/\(clientID)", data: responseData)

    let sut = AuthAdminClient.testing(http: transport)

    let client = try await sut.oauth.client(id: clientID)

    #expect(client.clientID == clientID)
    #expect(client.clientName == nil)
  }

  @Test
  func getOAuthClientWithoutRedirectUrisGrantTypesOrResponseTypes() async throws {
    let responseData = """
      {
        "client_id": "\(clientID)",
        "client_name": "Test Client",
        "client_type": "confidential",
        "token_endpoint_auth_method": "client_secret_post",
        "registration_type": "manual",
        "created_at": "2024-01-01T00:00:00.000Z",
        "updated_at": "2024-01-01T00:00:00.000Z"
      }
      """.data(using: .utf8)!

    transport.stub(.get, "admin/oauth/clients/\(clientID)", data: responseData)

    let sut = AuthAdminClient.testing(http: transport)

    let client = try await sut.oauth.client(id: clientID)

    #expect(client.clientID == clientID)
    #expect(client.redirectURIs == nil)
    #expect(client.grantTypes == nil)
    #expect(client.responseTypes == nil)
  }

  @Test
  func deleteOAuthClient() async throws {
    transport.stub(.delete, "admin/oauth/clients/\(clientID)", status: .noContent) {
      #"""
      curl \
      	--request DELETE \
      	--header "Authorization: Bearer supabase.secret.key" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.secret.key" \
      	"http://localhost:54321/auth/v1/admin/oauth/clients/E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
      """#
    }

    let sut = AuthAdminClient.testing(http: transport)

    try await sut.oauth.deleteClient(id: clientID)
  }

  @Test
  func regenerateOAuthClientSecret() async throws {
    let responseData = """
      {
        "client_id": "\(clientID)",
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

    transport.stub(.post, "admin/oauth/clients/\(clientID)/regenerate_secret", data: responseData) {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer supabase.secret.key" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.secret.key" \
      	"http://localhost:54321/auth/v1/admin/oauth/clients/E621E1F8-C36C-495A-93FC-0C247A3E6E5F/regenerate_secret"
      """#
    }

    let sut = AuthAdminClient.testing(http: transport)

    let client = try await sut.oauth.regenerateClientSecret(id: clientID)

    #expect(client.clientID == clientID)
    #expect(client.clientSecret == "new-secret456")
  }

  @Test
  func listOAuthClientsWithAnEmptyLinkHeader() async throws {
    let responseData = """
      {
        "clients": [],
        "aud": "authenticated"
      }
      """.data(using: .utf8)!

    transport.stub(.get, "admin/oauth/clients") { _, _ in
      (
        HTTPResponse(
          status: .ok,
          headerFields: [
            .contentType: "application/json",
            HTTPField.Name("x-total-count")!: "0",
            .link: "",
          ]),
        responseData
      )
    }

    let sut = AuthAdminClient.testing(http: transport)

    let response = try await sut.oauth.listClients()

    #expect(response.clients.isEmpty)
    #expect(response.nextPage == nil)
    #expect(response.lastPage == 0)
  }
}
