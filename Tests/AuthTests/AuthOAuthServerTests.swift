//
//  AuthOAuthServerTests.swift
//
//
//  Created by Guilherme Souza on 10/07/26.
//

import ConcurrencyExtras
import CustomDump
import Foundation
import Helpers
import InlineSnapshotTesting
import TestHelpers
import Testing

@testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct AuthOAuthServerTests {
  let clientId = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
  let userId = UUID(uuidString: "859F402D-B3DE-4105-A1B9-932836D9193B")!

  let transport = RecordingTransport()
  let storage = InMemoryTestStorage()

  private func makeSUT() -> AuthClient {
    AuthClient(
      configuration: .init(
        url: clientURL,
        storageKey: uniqueStorageKey(),
        headers: HTTPFields(["apikey": "supabase.publishable.key"]),
        storage: storage,
        autoRefresh: .manual,
        http: .init(transport: transport)),
      pkce: .live,
      platform: .live)
  }

  @Test
  func decodeOAuthAuthorizationDetails() throws {
    let json = """
      {
        "authorization_id": "abc123def456",
        "redirect_uri": "https://example.com/callback",
        "client": {
          "id": "\(clientId)",
          "name": "Test Client",
          "uri": "https://example.com",
          "logo_uri": "https://example.com/logo.png"
        },
        "user": {
          "id": "\(userId)",
          "email": "user@example.com"
        },
        "scope": "read write"
      }
      """.data(using: .utf8)!

    let response = try AuthClient.Configuration.jsonDecoder.decode(
      OAuthAuthorizationDetailsResponse.self, from: json
    )

    guard case .details(let details) = response else {
      Issue.record("Expected .details case, got \(response)")
      return
    }

    #expect(details.authorizationId == "abc123def456")
    #expect(details.redirectUri == URL(string: "https://example.com/callback"))
    #expect(details.client.id == clientId)
    #expect(details.client.name == "Test Client")
    #expect(details.client.uri == URL(string: "https://example.com"))
    #expect(details.client.logoUri == URL(string: "https://example.com/logo.png"))
    #expect(details.user.id == userId)
    #expect(details.user.email == "user@example.com")
    #expect(details.scope == "read write")
  }

  @Test
  func decodeOAuthAuthorizationDetailsWithMissingOptionalClientFields() throws {
    let json = """
      {
        "authorization_id": "abc123def456",
        "redirect_uri": "https://example.com/callback",
        "client": {
          "id": "\(clientId)",
          "name": "Test Client"
        },
        "user": {
          "id": "\(userId)",
          "email": "user@example.com"
        },
        "scope": "read"
      }
      """.data(using: .utf8)!

    let response = try AuthClient.Configuration.jsonDecoder.decode(
      OAuthAuthorizationDetailsResponse.self, from: json
    )

    guard case .details(let details) = response else {
      Issue.record("Expected .details case, got \(response)")
      return
    }

    #expect(details.client.uri == nil)
    #expect(details.client.logoUri == nil)
  }

  @Test
  func decodeOAuthAuthorizationDetailsWithoutClientNameUserEmailOrScope() throws {
    let json = """
      {
        "authorization_id": "abc123def456",
        "redirect_uri": "https://example.com/callback",
        "client": {
          "id": "\(clientId)"
        },
        "user": {
          "id": "\(userId)"
        }
      }
      """.data(using: .utf8)!

    let response = try AuthClient.Configuration.jsonDecoder.decode(
      OAuthAuthorizationDetailsResponse.self, from: json
    )

    guard case .details(let details) = response else {
      Issue.record("Expected .details case, got \(response)")
      return
    }

    #expect(details.authorizationId == "abc123def456")
    #expect(details.client.id == clientId)
    #expect(details.client.name == nil)
    #expect(details.user.id == userId)
    #expect(details.user.email == nil)
    #expect(details.scope == nil)
  }

  @Test
  func decodeOAuthAuthorizationDetailsAutoApproveRedirect() throws {
    let json = """
      { "redirect_url": "https://example.com/callback?code=abc123" }
      """.data(using: .utf8)!

    let response = try AuthClient.Configuration.jsonDecoder.decode(
      OAuthAuthorizationDetailsResponse.self, from: json
    )

    guard case .redirect(let redirect) = response else {
      Issue.record("Expected .redirect case, got \(response)")
      return
    }

    #expect(redirect.redirectURL == URL(string: "https://example.com/callback?code=abc123"))
  }

  @Test
  func decodeOAuthAuthorizationDetailsResponseSurfacesTheDetailsError() throws {
    let json = """
      {
        "authorization_id": "abc123def456",
        "redirect_uri": "https://example.com/callback",
        "client": {
          "id": "not-a-uuid",
          "name": "Test Client"
        },
        "user": {
          "id": "\(userId)",
          "email": "user@example.com"
        },
        "scope": "email"
      }
      """.data(using: .utf8)!

    let error = try #require(throws: DecodingError.self) {
      try AuthClient.Configuration.jsonDecoder.decode(
        OAuthAuthorizationDetailsResponse.self, from: json
      )
    }
    #expect("\(error)".lowercased().contains("uuid"), "got \(error)")
  }

  @Test
  func decodeOAuthGrant() throws {
    let json = """
      {
        "client": {
          "id": "\(clientId)",
          "name": "Test Client",
          "uri": "https://example.com",
          "logo_uri": "https://example.com/logo.png"
        },
        "scopes": ["read", "write"],
        "granted_at": "2024-01-01T00:00:00.000Z"
      }
      """.data(using: .utf8)!

    let grant = try AuthClient.Configuration.jsonDecoder.decode(OAuthGrant.self, from: json)

    #expect(grant.client.id == clientId)
    #expect(grant.scopes == ["read", "write"])
  }

  @Test
  func authorizationDetails() async throws {
    let responseData = """
      {
        "authorization_id": "abc123def456",
        "redirect_uri": "https://example.com/callback",
        "client": {
          "id": "\(clientId)",
          "name": "Test Client",
          "uri": "https://example.com",
          "logo_uri": "https://example.com/logo.png"
        },
        "user": {
          "id": "\(userId)",
          "email": "user@example.com"
        },
        "scope": "read write"
      }
      """.data(using: .utf8)!

    transport.stub(.get, "oauth/authorizations/abc123def456", data: responseData) {
      #"""
      curl \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.publishable.key" \
      	"http://localhost:54321/auth/v1/oauth/authorizations/abc123def456"
      """#
    }

    let sut = makeSUT()
    try await sut.seedSession(.valid)

    let response = try await sut.oauthServer.authorizationDetails(
      id: "abc123def456"
    )

    guard case .details(let details) = response else {
      Issue.record("Expected .details case, got \(response)")
      return
    }

    #expect(details.authorizationId == "abc123def456")
    #expect(details.client.name == "Test Client")
  }

  @Test
  func getAuthorizationDetailsSessionMissing() async throws {
    let sut = makeSUT()

    do {
      _ = try await sut.oauthServer.authorizationDetails(id: "abc123def456")
      Issue.record("Expected AuthError.sessionMissing")
    } catch let error as AuthError where error.kind == .sessionMissing {
    }
  }

  @Test
  func getAuthorizationDetailsNotFound() async throws {
    let responseData = """
      { "error_code": "oauth_authorization_not_found", "msg": "Authorization not found" }
      """.data(using: .utf8)!

    transport.stub(.get, "oauth/authorizations/missing", status: .notFound, data: responseData)

    let sut = makeSUT()
    try await sut.seedSession(.valid)

    do {
      _ = try await sut.oauthServer.authorizationDetails(id: "missing")
      Issue.record("Expected AuthError.server")
    } catch let error as AuthError {
      #expect(error.kind == .server)
      #expect(error.errorCode == .oauthAuthorizationNotFound)
    }
  }

  @Test
  func approveAuthorization() async throws {
    let responseData = """
      { "redirect_url": "https://example.com/callback?code=abc123" }
      """.data(using: .utf8)!

    transport.stub(.post, "oauth/authorizations/abc123def456/consent", data: responseData) {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 20" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.publishable.key" \
      	--data "{\"action\":\"approve\"}" \
      	"http://localhost:54321/auth/v1/oauth/authorizations/abc123def456/consent"
      """#
    }

    let sut = makeSUT()
    try await sut.seedSession(.valid)

    let redirect = try await sut.oauthServer.approveAuthorization(
      id: "abc123def456"
    )

    #expect(redirect.redirectURL == URL(string: "https://example.com/callback?code=abc123"))
  }

  @Test
  func denyAuthorization() async throws {
    let responseData = """
      {
        "redirect_url": "https://example.com/callback?error=access_denied&error_description=User+denied+the+request"
      }
      """.data(using: .utf8)!

    transport.stub(.post, "oauth/authorizations/abc123def456/consent", data: responseData) {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 17" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.publishable.key" \
      	--data "{\"action\":\"deny\"}" \
      	"http://localhost:54321/auth/v1/oauth/authorizations/abc123def456/consent"
      """#
    }

    let sut = makeSUT()
    try await sut.seedSession(.valid)

    // Denial must NOT throw — it's a successful API call, per RFC 6749 the
    // OAuth error is embedded in the redirect URL's query string.
    let redirect = try await sut.oauthServer.denyAuthorization(id: "abc123def456")

    #expect(redirect.redirectURL.query?.contains("error=access_denied") == true)
  }

  @Test
  func listGrants() async throws {
    let responseData = """
      [
        {
          "client": {
            "id": "\(clientId)",
            "name": "Test Client",
            "uri": "https://example.com",
            "logo_uri": "https://example.com/logo.png"
          },
          "scopes": ["read", "write"],
          "granted_at": "2024-01-01T00:00:00.000Z"
        }
      ]
      """.data(using: .utf8)!

    transport.stub(.get, "user/oauth/grants", data: responseData) {
      #"""
      curl \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.publishable.key" \
      	"http://localhost:54321/auth/v1/user/oauth/grants"
      """#
    }

    let sut = makeSUT()
    try await sut.seedSession(.valid)

    let grants = try await sut.oauthServer.listGrants()

    #expect(grants.count == 1)
    #expect(grants[0].client.id == clientId)
    #expect(grants[0].scopes == ["read", "write"])
  }

  @Test
  func revokeGrant() async throws {
    transport.stub(.delete, "user/oauth/grants", status: .noContent) {
      #"""
      curl \
      	--request DELETE \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.publishable.key" \
      	"http://localhost:54321/auth/v1/user/oauth/grants?client_id=E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
      """#
    }

    let sut = makeSUT()
    try await sut.seedSession(.valid)

    try await sut.oauthServer.revokeGrant(id: clientId)
  }

  @Test
  func revokeGrantNotFound() async throws {
    let responseData = """
      { "error_code": "oauth_consent_not_found", "msg": "No active grant found" }
      """.data(using: .utf8)!

    transport.stub(.delete, "user/oauth/grants", status: .notFound, data: responseData)

    let sut = makeSUT()
    try await sut.seedSession(.valid)

    do {
      try await sut.oauthServer.revokeGrant(id: clientId)
      Issue.record("Expected AuthError.server")
    } catch let error as AuthError {
      #expect(error.kind == .server)
      #expect(error.errorCode == .oauthConsentNotFound)
    }
  }
}
