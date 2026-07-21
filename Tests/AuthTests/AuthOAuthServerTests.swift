//
//  AuthOAuthServerTests.swift
//
//
//  Created by Guilherme Souza on 10/07/26.
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

extension AuthMockerTests {
  @Suite(.mockerSerialized)
  struct AuthOAuthServerTests {
    let clientId = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
    let userId = UUID(uuidString: "859F402D-B3DE-4105-A1B9-932836D9193B")!

    let storage = InMemoryLocalStorage()

    init() {
      Mocker.removeAll()
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
          "apikey": "supabase.publishable.key"
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

    // MARK: - Decoding

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
    func decodeOAuthAuthorizationDetailsAutoApproveRedirect() throws {
      // The server auto-approves (and returns a bare redirect) when the user
      // already has an active consent covering the requested scopes.
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
    func decodeOAuthAuthorizationDetailsResponseSurfacesBothErrorsWhenNeitherShapeMatches() throws {
      // `client.id` is not a valid UUID, so decoding as OAuthAuthorizationDetails
      // fails for a genuine reason (not just "this is the redirect shape");
      // there's no `redirect_url` key either, so the redirect fallback also
      // fails. Both underlying errors must be visible, not just the (less
      // useful) redirect-decode one.
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

      do {
        _ = try AuthClient.Configuration.jsonDecoder.decode(
          OAuthAuthorizationDetailsResponse.self, from: json
        )
        Issue.record("Expected decoding to throw")
      } catch let combined as AllDecodingAttemptsFailedError {
        #expect(combined.errors.count == 2)
        #expect(
          "\(combined.errors[0])".lowercased().contains("uuid"),
          "first attempt's error should mention the invalid UUID, got \(combined.errors[0])"
        )
      } catch {
        Issue.record("Expected AllDecodingAttemptsFailedError, got \(error)")
      }
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

    // MARK: - getAuthorizationDetails

    @Test
    func getAuthorizationDetails() async throws {
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

      Mock(
        url: clientURL.appendingPathComponent("oauth/authorizations/abc123def456"),
        statusCode: 200,
        data: [.get: responseData]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Authorization: Bearer accesstoken" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: supabase.publishable.key" \
        	"http://localhost:54321/auth/v1/oauth/authorizations/abc123def456"
        """#
      }
      .register()

      let sut = makeSUT()
      Dependencies[sut.clientID].sessionStorage.store(.validSession)

      let response = try await sut.oauthServer.getAuthorizationDetails(
        authorizationId: "abc123def456"
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
        _ = try await sut.oauthServer.getAuthorizationDetails(authorizationId: "abc123def456")
        Issue.record("Expected AuthError.sessionMissing")
      } catch AuthError.sessionMissing {
        // expected
      }
    }

    @Test
    func getAuthorizationDetailsNotFound() async throws {
      let responseData = """
        { "error_code": "oauth_authorization_not_found", "msg": "Authorization not found" }
        """.data(using: .utf8)!

      Mock(
        url: clientURL.appendingPathComponent("oauth/authorizations/missing"),
        statusCode: 404,
        data: [.get: responseData]
      )
      .register()

      let sut = makeSUT()
      Dependencies[sut.clientID].sessionStorage.store(.validSession)

      do {
        _ = try await sut.oauthServer.getAuthorizationDetails(authorizationId: "missing")
        Issue.record("Expected AuthError.api")
      } catch let AuthError.api(_, errorCode, _, _) {
        #expect(errorCode == .oauthAuthorizationNotFound)
      }
    }

    // MARK: - approveAuthorization / denyAuthorization

    @Test
    func approveAuthorization() async throws {
      let responseData = """
        { "redirect_url": "https://example.com/callback?code=abc123" }
        """.data(using: .utf8)!

      Mock(
        url: clientURL.appendingPathComponent("oauth/authorizations/abc123def456/consent"),
        statusCode: 200,
        data: [.post: responseData]
      )
      .snapshotRequest {
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
      .register()

      let sut = makeSUT()
      Dependencies[sut.clientID].sessionStorage.store(.validSession)

      let redirect = try await sut.oauthServer.approveAuthorization(
        authorizationId: "abc123def456"
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

      Mock(
        url: clientURL.appendingPathComponent("oauth/authorizations/abc123def456/consent"),
        statusCode: 200,
        data: [.post: responseData]
      )
      .snapshotRequest {
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
      .register()

      let sut = makeSUT()
      Dependencies[sut.clientID].sessionStorage.store(.validSession)

      // Denial must NOT throw — it's a successful API call, per RFC 6749 the
      // OAuth error is embedded in the redirect URL's query string.
      let redirect = try await sut.oauthServer.denyAuthorization(authorizationId: "abc123def456")

      #expect(redirect.redirectURL.query?.contains("error=access_denied") == true)
    }

    // MARK: - listGrants

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

      Mock(
        url: clientURL.appendingPathComponent("user/oauth/grants"),
        statusCode: 200,
        data: [.get: responseData]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Authorization: Bearer accesstoken" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: supabase.publishable.key" \
        	"http://localhost:54321/auth/v1/user/oauth/grants"
        """#
      }
      .register()

      let sut = makeSUT()
      Dependencies[sut.clientID].sessionStorage.store(.validSession)

      let grants = try await sut.oauthServer.listGrants()

      #expect(grants.count == 1)
      #expect(grants[0].client.id == clientId)
      #expect(grants[0].scopes == ["read", "write"])
    }

    // MARK: - revokeGrant

    @Test
    func revokeGrant() async throws {
      Mock(
        url: clientURL.appendingPathComponent("user/oauth/grants"),
        ignoreQuery: true,
        statusCode: 204,
        data: [.delete: Data()]
      )
      .snapshotRequest {
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
      .register()

      let sut = makeSUT()
      Dependencies[sut.clientID].sessionStorage.store(.validSession)

      try await sut.oauthServer.revokeGrant(clientId: clientId)
    }

    @Test
    func revokeGrantNotFound() async throws {
      let responseData = """
        { "error_code": "oauth_consent_not_found", "msg": "No active grant found" }
        """.data(using: .utf8)!

      Mock(
        url: clientURL.appendingPathComponent("user/oauth/grants"),
        ignoreQuery: true,
        statusCode: 404,
        data: [.delete: responseData]
      )
      .register()

      let sut = makeSUT()
      Dependencies[sut.clientID].sessionStorage.store(.validSession)

      do {
        try await sut.oauthServer.revokeGrant(clientId: clientId)
        Issue.record("Expected AuthError.api")
      } catch let AuthError.api(_, errorCode, _, _) {
        #expect(errorCode == .oauthConsentNotFound)
      }
    }
  }
}
