//
//  AuthOAuthServerTests.swift
//
//
//  Created by Guilherme Souza on 10/07/26.
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

final class AuthOAuthServerTests: XCTestCase {
  let clientId = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
  let userId = UUID(uuidString: "859F402D-B3DE-4105-A1B9-932836D9193B")!

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

  func testDecodeOAuthAuthorizationDetails() throws {
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
      XCTFail("Expected .details case, got \(response)")
      return
    }

    XCTAssertEqual(details.authorizationId, "abc123def456")
    XCTAssertEqual(details.redirectUri, URL(string: "https://example.com/callback"))
    XCTAssertEqual(details.client.id, clientId)
    XCTAssertEqual(details.client.name, "Test Client")
    XCTAssertEqual(details.client.uri, URL(string: "https://example.com"))
    XCTAssertEqual(details.client.logoUri, URL(string: "https://example.com/logo.png"))
    XCTAssertEqual(details.user.id, userId)
    XCTAssertEqual(details.user.email, "user@example.com")
    XCTAssertEqual(details.scope, "read write")
  }

  func testDecodeOAuthAuthorizationDetailsWithMissingOptionalClientFields() throws {
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
      XCTFail("Expected .details case, got \(response)")
      return
    }

    XCTAssertNil(details.client.uri)
    XCTAssertNil(details.client.logoUri)
  }

  func testDecodeOAuthAuthorizationDetailsAutoApproveRedirect() throws {
    // The server auto-approves (and returns a bare redirect) when the user
    // already has an active consent covering the requested scopes.
    let json = """
      { "redirect_url": "https://example.com/callback?code=abc123" }
      """.data(using: .utf8)!

    let response = try AuthClient.Configuration.jsonDecoder.decode(
      OAuthAuthorizationDetailsResponse.self, from: json
    )

    guard case .redirect(let redirect) = response else {
      XCTFail("Expected .redirect case, got \(response)")
      return
    }

    XCTAssertEqual(redirect.redirectURL, URL(string: "https://example.com/callback?code=abc123"))
  }

  func testDecodeOAuthGrant() throws {
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

    XCTAssertEqual(grant.client.id, clientId)
    XCTAssertEqual(grant.scopes, ["read", "write"])
  }

  // MARK: - getAuthorizationDetails

  func testGetAuthorizationDetails() async throws {
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

    sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let response = try await sut.oauthServer.getAuthorizationDetails(
      authorizationId: "abc123def456"
    )

    guard case .details(let details) = response else {
      XCTFail("Expected .details case, got \(response)")
      return
    }

    XCTAssertEqual(details.authorizationId, "abc123def456")
    XCTAssertEqual(details.client.name, "Test Client")
  }

  func testGetAuthorizationDetailsSessionMissing() async throws {
    sut = makeSUT()

    do {
      _ = try await sut.oauthServer.getAuthorizationDetails(authorizationId: "abc123def456")
      XCTFail("Expected AuthError.sessionMissing")
    } catch AuthError.sessionMissing {
      // expected
    }
  }

  func testGetAuthorizationDetailsNotFound() async throws {
    let responseData = """
      { "error_code": "oauth_authorization_not_found", "msg": "Authorization not found" }
      """.data(using: .utf8)!

    Mock(
      url: clientURL.appendingPathComponent("oauth/authorizations/missing"),
      statusCode: 404,
      data: [.get: responseData]
    )
    .register()

    sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    do {
      _ = try await sut.oauthServer.getAuthorizationDetails(authorizationId: "missing")
      XCTFail("Expected AuthError.api")
    } catch let AuthError.api(_, errorCode, _, _) {
      XCTAssertEqual(errorCode, .oauthAuthorizationNotFound)
    }
  }

  // MARK: - approveAuthorization / denyAuthorization

  func testApproveAuthorization() async throws {
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

    sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let redirect = try await sut.oauthServer.approveAuthorization(
      authorizationId: "abc123def456"
    )

    XCTAssertEqual(redirect.redirectURL, URL(string: "https://example.com/callback?code=abc123"))
  }

  func testDenyAuthorization() async throws {
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

    sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    // Denial must NOT throw — it's a successful API call, per RFC 6749 the
    // OAuth error is embedded in the redirect URL's query string.
    let redirect = try await sut.oauthServer.denyAuthorization(authorizationId: "abc123def456")

    XCTAssertEqual(redirect.redirectURL.query?.contains("error=access_denied"), true)
  }

  // MARK: - listGrants

  func testListGrants() async throws {
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

    sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let grants = try await sut.oauthServer.listGrants()

    XCTAssertEqual(grants.count, 1)
    XCTAssertEqual(grants[0].client.id, clientId)
    XCTAssertEqual(grants[0].scopes, ["read", "write"])
  }

  // MARK: - revokeGrant

  func testRevokeGrant() async throws {
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

    sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    try await sut.oauthServer.revokeGrant(clientId: clientId)
  }

  func testRevokeGrantNotFound() async throws {
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

    sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    do {
      try await sut.oauthServer.revokeGrant(clientId: clientId)
      XCTFail("Expected AuthError.api")
    } catch let AuthError.api(_, errorCode, _, _) {
      XCTAssertEqual(errorCode, .oauthConsentNotFound)
    }
  }
}
