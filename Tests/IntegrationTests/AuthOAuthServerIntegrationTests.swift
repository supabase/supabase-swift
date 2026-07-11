//
//  AuthOAuthServerIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 10/07/26.
//

import XCTest

@testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class AuthOAuthServerIntegrationTests: XCTestCase {
  let authClient = AuthClientIntegrationTests.makeClient()

  override func setUp() async throws {
    try await super.setUp()

    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil,
      "INTEGRATION_TESTS not defined."
    )
  }

  /// Performs a raw GET to `/oauth/authorize` with PKCE params, capturing the
  /// `authorization_id` from the 302 redirect's `Location` header — the
  /// endpoint that actually creates a pending `oauth_authorizations` row.
  /// `/oauth/authorize` is intentionally not part of the SDK's public
  /// surface (same as the JS port), so integration tests reach it directly.
  private func createPendingAuthorization(
    accessToken: String,
    clientId: UUID,
    redirectUri: String,
    scope: String
  ) async throws -> String {
    var components = URLComponents(
      url: URL(string: "\(DotEnv.SUPABASE_URL)/auth/v1/oauth/authorize")!,
      resolvingAgainstBaseURL: false
    )!
    components.queryItems = [
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "client_id", value: clientId.uuidString),
      URLQueryItem(name: "redirect_uri", value: redirectUri),
      URLQueryItem(name: "scope", value: scope),
      URLQueryItem(name: "state", value: "test-state"),
      URLQueryItem(name: "code_challenge", value: String(repeating: "a", count: 43)),
      URLQueryItem(name: "code_challenge_method", value: "plain"),
    ]

    var request = URLRequest(url: components.url!)
    request.setValue(DotEnv.SUPABASE_PUBLISHABLE_KEY, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

    let delegate = NoRedirectSessionDelegate()
    let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    let (_, response) = try await session.data(for: request)

    guard
      let httpResponse = response as? HTTPURLResponse,
      let location = httpResponse.value(forHTTPHeaderField: "Location"),
      let locationComponents = URLComponents(string: location),
      let authorizationId = locationComponents.queryItems?.first(where: {
        $0.name == "authorization_id"
      })?.value
    else {
      XCTFail("Expected a redirect with an authorization_id query param, got \(response)")
      throw AuthError.sessionMissing
    }

    return authorizationId
  }

  func testApproveAuthorizationFlow() async throws {
    let email = mockEmail()
    let password = mockPassword()
    try await signUpIfNeededOrSignIn(email: email, password: password)

    let serviceRoleClient = AuthClientIntegrationTests.makeClient(serviceRole: true)
    let redirectUri = "https://example.com/callback"
    let oauthClient = try await serviceRoleClient.admin.oauth.createClient(
      params: CreateOAuthClientParams(
        clientName: "Integration Test Client",
        redirectUris: [redirectUri]
      )
    )

    let session = try await authClient.session
    let authorizationId = try await createPendingAuthorization(
      accessToken: session.accessToken,
      clientId: oauthClient.clientId,
      redirectUri: redirectUri,
      scope: "read"
    )

    let detailsResponse = try await authClient.oauthServer.getAuthorizationDetails(
      authorizationId: authorizationId
    )

    guard case .details(let details) = detailsResponse else {
      XCTFail("Expected pending .details, got \(detailsResponse)")
      return
    }
    XCTAssertEqual(details.client.id, oauthClient.clientId)
    XCTAssertEqual(details.scope, "read")

    let approveRedirect = try await authClient.oauthServer.approveAuthorization(
      authorizationId: authorizationId
    )
    XCTAssertNotNil(approveRedirect.redirectURL)

    let grants = try await authClient.oauthServer.listGrants()
    XCTAssertTrue(grants.contains { $0.client.id == oauthClient.clientId })

    try await authClient.oauthServer.revokeGrant(clientId: oauthClient.clientId)

    let grantsAfterRevoke = try await authClient.oauthServer.listGrants()
    XCTAssertFalse(grantsAfterRevoke.contains { $0.client.id == oauthClient.clientId })

    _ = try await serviceRoleClient.admin.oauth.deleteClient(clientId: oauthClient.clientId)
  }

  func testDenyAuthorizationFlow() async throws {
    let email = mockEmail()
    let password = mockPassword()
    try await signUpIfNeededOrSignIn(email: email, password: password)

    let serviceRoleClient = AuthClientIntegrationTests.makeClient(serviceRole: true)
    let redirectUri = "https://example.com/callback"
    let oauthClient = try await serviceRoleClient.admin.oauth.createClient(
      params: CreateOAuthClientParams(
        clientName: "Integration Test Client (deny)",
        redirectUris: [redirectUri]
      )
    )

    let session = try await authClient.session
    let authorizationId = try await createPendingAuthorization(
      accessToken: session.accessToken,
      clientId: oauthClient.clientId,
      redirectUri: redirectUri,
      scope: "read"
    )

    // Denial must not throw — it's a successful call carrying an
    // access_denied error in the redirect URL.
    let denyRedirect = try await authClient.oauthServer.denyAuthorization(
      authorizationId: authorizationId
    )
    XCTAssertEqual(denyRedirect.redirectURL.query?.contains("error=access_denied"), true)

    _ = try await serviceRoleClient.admin.oauth.deleteClient(clientId: oauthClient.clientId)
  }

  // ponytail: `AuthClientIntegrationTests`'s equivalents are `private` on that
  // type, so they aren't reachable from here. Duplicated (kept minimal)
  // rather than widening access on the other file for three helper methods.

  @discardableResult
  private func signUpIfNeededOrSignIn(
    email: String,
    password: String
  ) async throws -> AuthResponse {
    do {
      let session = try await authClient.signIn(email: email, password: password)
      return .session(session)
    } catch {
      return try await authClient.signUp(email: email, password: password)
    }
  }

  private func mockEmail(length: Int = Int.random(in: 5...10)) -> String {
    var username = ""
    for _ in 0..<length {
      let randomAscii = Int.random(in: 97...122)  // ASCII values for lowercase letters
      let randomCharacter = Character(UnicodeScalar(randomAscii)!)
      username.append(randomCharacter)
    }
    return "\(username)@supabase.com"
  }

  private func mockPassword(length: Int = 12) -> String {
    let allowedCharacters =
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+"
    var password = ""

    for _ in 0..<length {
      let randomIndex = Int.random(in: 0..<allowedCharacters.count)
      let character = allowedCharacters[
        allowedCharacters.index(
          allowedCharacters.startIndex,
          offsetBy: randomIndex
        )
      ]
      password.append(character)
    }

    return password
  }
}

/// Suppresses automatic redirect-following so the `Location` header of a
/// 302 response can be inspected directly.
private final class NoRedirectSessionDelegate: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest
  ) async -> URLRequest? {
    nil
  }
}
