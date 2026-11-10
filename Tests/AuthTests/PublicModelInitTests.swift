//
//  PublicModelInitTests.swift
//  Auth
//

import Foundation
import Testing

// A plain `import Auth`, not `@testable`: the tests see only the public API, the way an app
// building fixtures and previews does.
@_spi(Experimental) import Auth

@Suite struct PublicModelInitTests {
  private let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  private let date = Date(timeIntervalSince1970: 1_700_000_000)
  private let url = URL(string: "https://example.com")!

  @Test func mfaModelsAreBuildableAndMutable() {
    var factor = Factor(
      id: id, friendlyName: nil, factorType: .totp, status: .verified, createdAt: date,
      updatedAt: date)
    factor.friendlyName = "phone"
    #expect(factor.friendlyName == "phone")

    var totp = TOTPEnrollment(id: id, qrCode: "<svg/>", secret: "s", uri: "otpauth://x")
    totp.secret = "t"
    #expect(totp.secret == "t")

    var phone = PhoneEnrollment(id: id, phone: "+15550100")
    phone.phone = "+15550101"
    #expect(phone.phone == "+15550101")

    let challenge = MFAChallenge(id: id, factorType: .totp, expiresAt: date)
    #expect(challenge.webauthn == nil)

    var unenroll = AuthMFAUnenrollResponse(id: id)
    unenroll.id = UUID()
    #expect(unenroll.id != id)

    var status = AuthMFARecoveryCodesStatusResponse(id: id, total: 10, remaining: 10)
    status.remaining = 9
    #expect(status.remaining == 9)

    var generated = AuthMFARecoveryCodesGenerateResponse(id: id, total: 1, codes: ["a"])
    generated.codes = ["b"]
    generated.friendlyName = "codes"
    #expect(generated.codes == ["b"])

    var factors = MFAFactors(verified: [factor], unverified: [])
    factors.unverified = [factor]
    #expect(factors.all.count == 2)

    var amr = AMREntry(method: .password, timestamp: date)
    amr.method = .totp
    #expect(amr.method == .totp)

    var level = AssuranceLevelInfo(
      currentLevel: .aal1, nextLevel: .aal2, currentAuthenticationMethods: [amr])
    level.currentLevel = .aal2
    #expect(level.currentLevel == .aal2)

    var weak = WeakPassword(reasons: ["length"])
    weak.reasons = []
    #expect(weak.reasons.isEmpty)
  }

  @Test func pagingAndAdminModelsAreBuildableAndMutable() {
    var flow = OAuthFlow(id: id, url: url)
    flow.url = URL(string: "https://example.org")!
    #expect(flow.url.host == "example.org")

    var params = PageParams(page: 1)
    params.perPage = 50
    #expect(params.perPage == 50)

    var page = UserPage(users: [], audience: "", nextPage: nil, lastPage: 1, total: 0)
    page.total = 3
    #expect(page.total == 3)

    var link = GenerateLinkProperties(
      actionLink: url, emailOTP: "123456", hashedToken: "h", verificationType: .magiclink)
    link.redirectTo = url
    #expect(link.redirectTo == url)
  }

  @Test func oauthModelsAreBuildableAndMutable() {
    var client = OAuthClient(
      clientID: id, clientType: .confidential, tokenEndpointAuthMethod: "none",
      registrationType: .manual, createdAt: date, updatedAt: date)
    client.clientName = "App"
    #expect(client.clientName == "App")

    var list = ListOAuthClientsPaginatedResponse(
      clients: [client], audience: "", nextPage: nil, lastPage: 1, total: 1)
    list.clients = []
    #expect(list.clients.isEmpty)

    let authClient = OAuthAuthorizationClient(id: id)
    let user = OAuthAuthorizationUser(id: id)

    var details = OAuthAuthorizationDetails(
      authorizationID: "a", redirectURI: url, client: authClient, user: user)
    details.scope = "openid"
    #expect(details.scope == "openid")

    var redirect = OAuthRedirect(redirectURL: url)
    redirect.redirectURL = URL(string: "https://example.org")!
    #expect(redirect.redirectURL.host == "example.org")

    var grant = OAuthGrant(client: authClient, scopes: [], grantedAt: date)
    grant.scopes = ["openid"]
    #expect(grant.scopes == ["openid"])
  }

  @Test func jwtAndClaimsModelsAreBuildableAndMutable() {
    var jwk = JWK(kty: "RSA")
    jwk.kid = "key-1"
    var keys = JWKS(keys: [jwk])
    keys.keys = []
    #expect(keys.keys.isEmpty)

    var header = JWTHeader(alg: "RS256")
    header.typ = "JWT"
    #expect(header.typ == "JWT")

    var claims = VerifiedClaims(
      subject: "sub", audience: [], expiresAt: date, amr: [], appMetadata: [:], userMetadata: [:],
      additionalClaims: [:], header: header, signature: Data())
    claims.email = "a@b.co"
    #expect(claims.email == "a@b.co")
  }

  @Test func decodeOnlyModelsAreBuildableAndMutable() {
    var provider = CustomProvider(
      id: id, providerType: .oauth2, identifier: "custom:acme", name: "Acme", clientID: "client",
      acceptableClientIDs: [], scopes: [], customClaimsAllowlist: [], pkceEnabled: true,
      attributeMapping: [:], authorizationParams: [:], enabled: true, emailOptional: false,
      skipNonceCheck: false, createdAt: date, updatedAt: date)
    provider.enabled = false
    #expect(!provider.enabled)

    var link = GenerateLinkResponse(
      properties: GenerateLinkProperties(
        actionLink: url, emailOTP: "1", hashedToken: "h", verificationType: .magiclink),
      user: Session.valid.user)
    link.properties.emailOTP = "2"
    #expect(link.properties.emailOTP == "2")
  }

  @Test func experimentalPasskeyOptionsAreBuildableAndMutable() {
    var registration = PasskeyRegistrationOptions(
      challengeID: id, options: .null, expiresAt: date)
    registration.expiresAt = date.addingTimeInterval(60)
    #expect(registration.expiresAt > date)

    var authentication = PasskeyAuthenticationOptions(
      challengeID: id, options: .null, expiresAt: date)
    authentication.challengeID = UUID()
    #expect(authentication.challengeID != id)
  }

  @Test func customProviderModelsAreMutable() {
    var document = OIDCDiscoveryDocument(
      issuer: "https://issuer", authorizationEndpoint: url, tokenEndpoint: url, jwksURI: url)
    document.userinfoEndpoint = url
    #expect(document.userinfoEndpoint == url)
  }

  @Test func experimentalWebAuthnModelsAreBuildableAndMutable() {
    var data = WebAuthnChallengeResponseData(type: .create, credentialOptions: .null)
    data.type = .request
    #expect(data.type == .request)

    var challenge = MFAChallenge(
      id: id, factorType: .webAuthn, expiresAt: date, webauthn: data)
    challenge.webauthn = nil
    #expect(challenge.webauthn == nil)
  }
}
