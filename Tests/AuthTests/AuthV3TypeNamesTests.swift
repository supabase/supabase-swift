import Foundation
import TestHelpers
import Testing

@testable import Auth

@Suite
struct AuthV3TypeNamesTests {
  let encoder = AuthClient.Configuration.jsonEncoder
  let decoder = AuthClient.Configuration.jsonDecoder

  @Test
  func v3TypeNamesAreTheV2Types() {
    let event: AuthEvent = AuthChangeEvent.signedIn
    #expect(event == .signedIn)
    #expect(AuthEvent.tokenRefreshed.rawValue == "TOKEN_REFRESHED")

    let phoneType: PhoneOTPType = MobileOTPType.phoneChange
    #expect(phoneType == .phoneChange)

    let resendType: ResendPhoneType = ResendMobileType.sms
    #expect(resendType == .sms)

    let link: GenerateLink = GenerateLinkParams.recovery(email: "user@example.com")
    #expect(link.body.email == "user@example.com")

    let result: OAuthAuthorizationDetailsResult = OAuthAuthorizationDetailsResponse.redirect(
      OAuthRedirect(redirectURL: URL(string: "https://example.com/callback")!))
    #expect(
      result == .redirect(OAuthRedirect(redirectURL: URL(string: "https://example.com/callback")!)))
  }

  @Test
  func authEventSwitchStaysExhaustive() {
    func name(_ event: AuthEvent) -> String {
      switch event {
      case .initialSession, .passwordRecovery, .signedIn, .signedOut, .tokenRefreshed,
        .userUpdated, .mfaChallengeVerified:
        "known"
      case .userDeleted:
        "deleted"
      }
    }
    #expect(name(.signedOut) == "known")
  }

  @Test
  func userPage() {
    let page = UserPage(users: [], audience: "authenticated", nextPage: 2, lastPage: 3, total: 40)
    #expect(page.audience == "authenticated")
    #expect(page.aud == "authenticated")
    #expect(page.nextPage == 2)
    #expect(page.lastPage == 3)
    #expect(page.total == 40)

    let old: ListUsersPaginatedResponse = page
    #expect(old == page)
  }

  @Test
  func userAudienceKeepsTheWireFormat() throws {
    var user = User(fromMockNamed: "user")
    #expect(user.audience == user.aud)

    user.audience = "custom"
    #expect(user.aud == "custom")

    let object = try #require(
      try JSONSerialization.jsonObject(with: encoder.encode(user)) as? [String: Any])
    #expect(object["aud"] as? String == "custom")
    #expect(object["audience"] == nil)
    #expect(try decoder.decode(User.self, from: encoder.encode(user)).audience == "custom")
  }

  @Test
  func userIdentityNamesKeepTheWireFormat() throws {
    let userID = UUID()
    var identity = UserIdentity(
      id: "provider-user",
      identityId: UUID(),
      userId: userID,
      identityData: [:],
      provider: "github",
      createdAt: nil,
      lastSignInAt: nil,
      updatedAt: nil
    )
    #expect(identity.userID == userID)
    #expect(identity.userId == userID)
    #expect(identity.providerUserID == "provider-user")

    identity.providerUserID = "other"
    #expect(identity.id == "other")

    let object = try #require(
      try JSONSerialization.jsonObject(with: encoder.encode(identity)) as? [String: Any])
    #expect(object["user_id"] as? String == userID.uuidString)
    #expect(object["id"] as? String == "other")
    #expect(try decoder.decode(UserIdentity.self, from: encoder.encode(identity)) == identity)
  }

  @Test
  func oauthClientNamesKeepTheWireFormat() throws {
    let json = Data(
      """
      {
        "client_id": "9DE5F7C3-6A8C-4F0B-9F0B-0B1F6E3C1A11",
        "client_name": "App",
        "client_type": "confidential",
        "token_endpoint_auth_method": "client_secret_basic",
        "registration_type": "manual",
        "client_uri": "https://example.com",
        "logo_uri": "https://example.com/logo.png",
        "redirect_uris": ["https://example.com/callback", "myapp://callback"],
        "grant_types": ["authorization_code"],
        "response_types": ["code"],
        "created_at": "2025-01-01T00:00:00.000Z",
        "updated_at": "2025-01-01T00:00:00.000Z"
      }
      """.utf8)

    let client = try decoder.decode(OAuthClient.self, from: json)
    #expect(client.clientID == UUID(uuidString: "9DE5F7C3-6A8C-4F0B-9F0B-0B1F6E3C1A11"))
    #expect(client.clientId == client.clientID)
    #expect(client.clientURI == URL(string: "https://example.com"))
    #expect(client.clientUri == "https://example.com")
    #expect(client.logoURI == URL(string: "https://example.com/logo.png"))
    #expect(client.logoUri == "https://example.com/logo.png")
    #expect(
      client.redirectURIs == [
        URL(string: "https://example.com/callback")!, URL(string: "myapp://callback")!,
      ])
    #expect(client.redirectUris == ["https://example.com/callback", "myapp://callback"])

    let object = try #require(
      try JSONSerialization.jsonObject(with: encoder.encode(client)) as? [String: Any])
    #expect(object["client_id"] as? String == "9DE5F7C3-6A8C-4F0B-9F0B-0B1F6E3C1A11")
    #expect(object["client_uri"] as? String == "https://example.com")
    #expect(object["logo_uri"] as? String == "https://example.com/logo.png")
    #expect(
      object["redirect_uris"] as? [String] == ["https://example.com/callback", "myapp://callback"])
    #expect(try decoder.decode(OAuthClient.self, from: encoder.encode(client)) == client)
  }

  @Test
  func oauthAuthorizationNamesKeepTheWireFormat() throws {
    let json = Data(
      """
      {
        "authorization_id": "abc123",
        "redirect_uri": "https://example.com/callback",
        "client": {
          "id": "9DE5F7C3-6A8C-4F0B-9F0B-0B1F6E3C1A11",
          "name": "App",
          "uri": "https://example.com",
          "logo_uri": "https://example.com/logo.png"
        },
        "user": {"id": "9DE5F7C3-6A8C-4F0B-9F0B-0B1F6E3C1A12", "email": "user@example.com"},
        "scope": "openid"
      }
      """.utf8)

    let details = try decoder.decode(OAuthAuthorizationDetails.self, from: json)
    #expect(details.authorizationID == "abc123")
    #expect(details.authorizationId == "abc123")
    #expect(details.redirectURI == URL(string: "https://example.com/callback"))
    #expect(details.redirectUri == details.redirectURI)
    #expect(details.client.logoURI == URL(string: "https://example.com/logo.png"))
    #expect(details.client.logoUri == details.client.logoURI)

    let object = try #require(
      try JSONSerialization.jsonObject(with: encoder.encode(details)) as? [String: Any])
    #expect(object["authorization_id"] as? String == "abc123")
    #expect(object["redirect_uri"] as? String == "https://example.com/callback")
    #expect(
      (object["client"] as? [String: Any])?["logo_uri"] as? String == "https://example.com/logo.png"
    )
  }

  @Test
  func publicInitializers() {
    let jwk = JWK(kty: "RSA", kid: "key-1")
    #expect(jwk.kid == "key-1")
    #expect(jwk.n == nil)

    var jwks = JWKS(keys: [jwk])
    jwks.keys.append(JWK(kty: "EC"))
    #expect(jwks.keys.count == 2)

    let header = JWTHeader(alg: "RS256", kid: "key-1")
    #expect(header.typ == nil)

    var weakPassword = WeakPassword(reasons: ["length"])
    weakPassword.reasons.append("pwned")
    #expect(weakPassword.reasons == ["length", "pwned"])
  }

  @Test
  func authenticatorAssuranceLevel() {
    let level: AuthenticatorAssuranceLevel = "aal2"
    #expect(level == .aal2)
    #expect(AuthenticatorAssuranceLevel.aal1.rawValue == "aal1")
    #expect(AuthenticatorAssuranceLevel(rawValue: "aal3").rawValue == "aal3")
  }

  @Test
  func configurationPropertiesAreMutable() {
    var configuration = AuthClient.Configuration(
      url: URL(string: "https://example.com")!, localStorage: InMemoryLocalStorage())
    configuration.autoRefreshToken = false
    configuration.redirectToURL = URL(string: "myapp://callback")
    #expect(configuration.autoRefreshToken == false)
    #expect(configuration.redirectToURL == URL(string: "myapp://callback"))
  }
}
