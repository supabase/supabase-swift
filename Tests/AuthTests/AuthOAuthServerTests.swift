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
}
