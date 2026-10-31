//
//  AuthAPITests.swift
//  AuthTests
//
//  Created by Guilherme Souza on 26/10/26.
//

import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@_spi(Experimental) @testable import Auth

@Suite
struct AuthAPITests {
  let api = AuthAPI(
    url: URL(string: "http://localhost:54321/auth/v1")!,
    headers: ["apikey": "dummy.api.key"],
    defaultRedirectURL: URL(string: "https://example.com/callback"),
    encoder: AuthClient.Configuration.jsonEncoder,
    decoder: AuthClient.Configuration.jsonDecoder
  )

  let pkce = PKCEChallenge(codeChallenge: "challenge", codeChallengeMethod: "s256")
  let id = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!

  /// The head of every request the SDK sends.
  func everyRequest() throws -> [HTTPTypes.HTTPRequest] {
    let token = "access-token"
    let credential: JSONValue = ["id": "credential-id"]
    return try [
      api.signUp(
        email: "a@b.c", password: "p", userMetadata: [:], redirectTo: nil, captchaToken: nil,
        pkce: pkce
      ).head,
      api.signUp(phone: "1", password: "p", channel: .sms, userMetadata: [:], captchaToken: nil)
        .head,
      api.signInAnonymously(userMetadata: [:], captchaToken: nil).head,
      api.signInWithPassword(email: "a@b.c", password: "p", captchaToken: nil).head,
      api.signInWithIDToken(
        credentials: IDTokenCredentials(provider: .apple, idToken: "t")
      ).head,
      api.signInWithWeb3(
        credentials: Web3Credentials(chain: .solana, message: "m", signature: "s")
      ).head,
      api.exchangeCodeForSession(authCode: "c", codeVerifier: "v").head,
      api.refreshSession(refreshToken: "r").head,
      api.signOut(accessToken: token, scope: .global).head,
      api.signInWithOTP(
        email: "a@b.c", redirectTo: nil, shouldCreateUser: true, userMetadata: [:],
        captchaToken: nil, pkce: nil
      ).head,
      api.signInWithOTP(
        phone: "1", channel: .sms, shouldCreateUser: true, userMetadata: [:], captchaToken: nil
      ).head,
      api.verifyOTP(email: "a@b.c", token: "1", type: .email, redirectTo: nil, captchaToken: nil)
        .head,
      api.verifyOTP(phone: "1", token: "1", type: .sms, captchaToken: nil).head,
      api.verifyOTP(tokenHash: "h", type: .email).head,
      api.resend(email: "a@b.c", type: .signup, redirectTo: nil, captchaToken: nil, pkce: nil).head,
      api.resend(phone: "1", type: .sms, captchaToken: nil).head,
      api.resetPasswordForEmail("a@b.c", redirectTo: nil, captchaToken: nil, pkce: nil).head,
      api.reauthenticate(accessToken: token).head,
      api.signInWithSSO(domain: "d", redirectTo: nil, captchaToken: nil, pkce: nil).head,
      api.linkIdentityURL(
        provider: .github, scopes: nil, redirectTo: nil, queryParams: [], pkce: nil,
        accessToken: token
      ).head,
      api.user(accessToken: token).head,
      api.updateUser(UserAttributes(), redirectTo: nil, pkce: nil, accessToken: token).head,
      api.unlinkIdentity(
        UserIdentity(
          id: "1", identityId: id, userId: id, identityData: [:], provider: "email",
          createdAt: Date(), lastSignInAt: Date(), updatedAt: Date()),
        accessToken: token
      ).head,
      api.jwks().head,
      api.oauthAuthorizationDetails(id: "a", accessToken: token).head,
      api.oauthConsent(authorizationId: "a", action: "approve", accessToken: token).head,
      api.oauthGrants(accessToken: token).head,
      api.revokeOAuthGrant(clientId: id, accessToken: token).head,
      api.enrollFactor(.totp(), decoding: TOTPEnrollment.self, accessToken: token).head,
      api.challengeFactor(factorID: id, channel: nil, webAuthn: nil, accessToken: token).head,
      api.verifyFactor(factorID: id, challengeID: id, code: "1", accessToken: token).head,
      api.unenrollFactor(factorID: id, accessToken: token).head,
      api.recoveryCodesStatus(accessToken: token).head,
      api.generateRecoveryCodes(friendlyName: nil, accessToken: token).head,
      api.verifyRecoveryCode("c", accessToken: token).head,
      api.regenerateRecoveryCodes(accessToken: token).head,
      api.unenrollRecoveryCodes(accessToken: token).head,
      api.passkeyRegistrationOptions(accessToken: token).head,
      api.verifyPasskeyRegistration(
        challengeId: "c", credentialResponse: credential, accessToken: token
      ).head,
      api.passkeyAuthenticationOptions().head,
      api.verifyPasskeyAuthentication(challengeId: "c", credentialResponse: credential).head,
      api.listPasskeys(accessToken: token).head,
      api.renamePasskey(id: id, friendlyName: "n", accessToken: token).head,
      api.deletePasskey(id: id, accessToken: token).head,
      api.adminUser(id: id).head,
      api.adminUpdateUser(id: id, attributes: AdminUserAttributes()).head,
      api.adminCreateUser(attributes: AdminUserAttributes()).head,
      api.adminInviteUser(email: "a@b.c", data: nil, redirectTo: nil).head,
      api.adminDeleteUser(id: id, shouldSoftDelete: false).head,
      api.adminListUsers(params: nil).head,
      api.adminGenerateLink(params: .magicLink(email: "a@b.c")).head,
      api.adminListFactors(userId: id).head,
      api.adminDeleteFactor(id: id, userId: id).head,
      api.adminListPasskeys(userId: id).head,
      api.adminDeletePasskey(id: id, userId: id).head,
      api.adminListOAuthClients(params: nil).head,
      api.adminCreateOAuthClient(
        params: CreateOAuthClientParams(clientName: "n", redirectUris: [])
      ).head,
      api.adminOAuthClient(id: id).head,
      api.adminUpdateOAuthClient(id: id, params: UpdateOAuthClientParams()).head,
      api.adminDeleteOAuthClient(id: id).head,
      api.adminRegenerateOAuthClientSecret(id: id).head,
    ]
  }

  @Test
  func everyRequestSendsTheAPIVersionAndTheAPIKey() throws {
    for head in try everyRequest() {
      #expect(head.headerFields[.apiVersionHeaderName] == "2024-01-01", "\(head.path ?? "")")
      #expect(head.headerFields[HTTPField.Name("apikey")!] == "dummy.api.key", "\(head.path ?? "")")
    }
  }

  @Test
  func configuredAPIVersionIsKept() {
    let api = AuthAPI(
      url: URL(string: "http://localhost:54321/auth/v1")!,
      headers: ["X-Supabase-Api-Version": "2025-01-01"],
      defaultRedirectURL: nil,
      encoder: JSONEncoder(),
      decoder: JSONDecoder()
    )

    #expect(api.jwks().head.headerFields[.apiVersionHeaderName] == "2025-01-01")
  }

  @Test
  func authorizeURLIsABrowserURLWithoutHeaders() throws {
    let url = try api.authorizeURL(
      provider: .github, scopes: "read", redirectTo: nil, queryParams: [("prompt", "consent")],
      pkce: pkce)

    #expect(
      url.absoluteString
        == "http://localhost:54321/auth/v1/authorize?provider=github&scopes=read&redirect_to=https://example.com/callback&code_challenge=challenge&code_challenge_method=s256&prompt=consent"
    )
  }

  @Test
  func requestFieldsUseTheServerSpelling() throws {
    let signUp = try api.signUp(
      email: "a@b.c", password: "p", userMetadata: [:], redirectTo: nil, captchaToken: "captcha",
      pkce: pkce)
    #expect(query(signUp) == ["redirect_to": "https://example.com/callback"])
    #expect(
      try body(signUp) == [
        "email": "a@b.c", "password": "p",
        "gotrue_meta_security": ["captcha_token": "captcha"],
        "code_challenge": "challenge", "code_challenge_method": "s256",
      ])

    let otp = try api.signInWithOTP(
      email: "a@b.c", redirectTo: nil, shouldCreateUser: false, userMetadata: [:],
      captchaToken: nil, pkce: nil)
    #expect(try body(otp) == ["email": "a@b.c", "create_user": false])

    let sso = try api.signInWithSSO(
      domain: "example.com", redirectTo: nil, captchaToken: nil, pkce: nil)
    #expect(sso.head.path == "/auth/v1/sso")
    #expect(
      try body(sso) == [
        "domain": "example.com", "redirect_to": "https://example.com/callback",
        "skip_http_redirect": true,
      ])

    let verify = try api.verifyOTP(
      email: "a@b.c", token: "1", type: .email, redirectTo: nil, captchaToken: nil)
    #expect(query(verify).isEmpty)
    #expect(
      try body(verify) == [
        "email": "a@b.c", "token": "1", "type": "email",
        "redirect_to": "https://example.com/callback",
      ])

    let link = try api.linkIdentityURL(
      provider: .github, scopes: nil, redirectTo: nil, queryParams: [], pkce: nil,
      accessToken: "token")
    #expect(
      query(link) == [
        "provider": "github", "redirect_to": "https://example.com/callback",
        "skip_http_redirect": "true",
      ])
    #expect(link.head.headerFields[.authorization] == "Bearer token")
  }

  @Test
  func errorResponseDecodesThroughErrorDecoder() throws {
    let request = try api.signInWithOTP(
      phone: "1", channel: .sms, shouldCreateUser: false, userMetadata: [:], captchaToken: nil)

    let error = try #require(throws: AuthError.self) {
      try request.decode(
        HTTPTypes.HTTPResponse(
          status: .unprocessableContent, headerFields: [.contentType: "application/json"]),
        // cspell:ignore Signups
        Data(#"{"code":"otp_disabled","message":"Signups not allowed for otp"}"#.utf8)
      )
    }
    #expect(error.errorCode == .otpDisabled)
    #expect(error.response?.statusCode == 422)
  }

  @Test
  func listUsersReadsPaginationFromHeaders() throws {
    let response = try api.adminListUsers(params: nil).decode(
      HTTPTypes.HTTPResponse(
        status: .ok,
        headerFields: [
          .xTotalCount: "120",
          .link:
            #"</admin/users?page=2&per_page=50>; rel="next", </admin/users?page=3&per_page=50>; rel="last""#,
        ]),
      Data(#"{"users":[],"aud":"authenticated"}"#.utf8)
    )

    #expect(response.total == 120)
    #expect(response.nextPage == 2)
    #expect(response.lastPage == 3)
  }

  @Test
  func userMetadataEncodesAsDataAndIsOmittedWhenEmpty() throws {
    let metadata: JSONObject = ["name": "Jane"]

    let email = try api.signUp(
      email: "a@b.c", password: "p", userMetadata: metadata, redirectTo: nil, captchaToken: nil,
      pkce: nil)
    #expect(try body(email) == ["email": "a@b.c", "password": "p", "data": ["name": "Jane"]])

    let phone = try api.signUp(
      phone: "1", password: "p", channel: .whatsapp, userMetadata: [:], captchaToken: nil)
    #expect(try body(phone) == ["phone": "1", "password": "p", "channel": "whatsapp"])

    let anonymous = try api.signInAnonymously(userMetadata: metadata, captchaToken: nil)
    #expect(try body(anonymous) == ["data": ["name": "Jane"]])
    #expect(try body(api.signInAnonymously(userMetadata: [:], captchaToken: nil)) == [:])

    let otp = try api.signInWithOTP(
      phone: "1", channel: .sms, shouldCreateUser: true, userMetadata: metadata,
      captchaToken: nil)
    #expect(
      try body(otp) == [
        "phone": "1", "channel": "sms", "create_user": true, "data": ["name": "Jane"],
      ])

    let update = try api.updateUser(
      UserAttributes(userMetadata: metadata), redirectTo: nil, pkce: nil, accessToken: "t")
    #expect(try body(update) == ["data": ["name": "Jane"]])
    let emptyUpdate = try api.updateUser(
      UserAttributes(email: "a@b.c", userMetadata: [:]), redirectTo: nil, pkce: nil,
      accessToken: "t")
    #expect(try body(emptyUpdate) == ["email": "a@b.c"])
  }

  @Test
  func credentialsSendTheCaptchaTokenAsGotrueMetaSecurity() throws {
    let idToken = try api.signInWithIDToken(
      credentials: IDTokenCredentials(
        provider: .apple, idToken: "id", nonce: "n", accessToken: "at", captchaToken: "captcha"))
    #expect(
      try body(idToken) == [
        "provider": "apple", "id_token": "id", "nonce": "n", "access_token": "at",
        "gotrue_meta_security": ["captcha_token": "captcha"], "link_identity": false,
      ])

    let linked = try api.signInWithIDToken(
      credentials: IDTokenCredentials(provider: "https://issuer.example.com", idToken: "id"),
      linkingTo: "t")
    #expect(
      try body(linked) == [
        "provider": "https://issuer.example.com", "id_token": "id", "link_identity": true,
      ])

    let web3 = try api.signInWithWeb3(
      credentials: Web3Credentials(
        chain: .ethereum, message: "m", signature: "s", captchaToken: "captcha"))
    #expect(
      try body(web3) == [
        "chain": "ethereum", "message": "m", "signature": "s",
        "gotrue_meta_security": ["captcha_token": "captcha"],
      ])
  }

  @Test
  func signUpDecodesASessionOrAUser() throws {
    let request = try api.signUp(
      email: "a@b.c", password: "p", userMetadata: [:], redirectTo: nil, captchaToken: nil,
      pkce: nil)

    let session = try request.decode(ok, json(named: "session"))
    guard case .signedIn = session else {
      Issue.record("Expected .signedIn, got \(session)")
      return
    }

    let user = try request.decode(ok, json(named: "user"))
    guard case .confirmationRequired = user else {
      Issue.record("Expected .confirmationRequired, got \(user)")
      return
    }
    #expect(user.user.id == UUID(uuidString: "859F402D-B3DE-4105-A1B9-932836D9193B"))

    // The obfuscated user GoTrue returns for an email that is already registered.
    var obfuscated = try #require(
      JSONSerialization.jsonObject(with: json(named: "user")) as? [String: Any])
    obfuscated["identities"] = [Any]()
    let fakeUser = try request.decode(ok, JSONSerialization.data(withJSONObject: obfuscated))
    #expect(fakeUser.session == nil)
    #expect(fakeUser.user.identities == [])
  }

  @Test
  func signUpSurfacesTheSessionErrorForAMalformedSession() throws {
    let request = try api.signUp(
      email: "a@b.c", password: "p", userMetadata: [:], redirectTo: nil, captchaToken: nil,
      pkce: nil)
    var session = try #require(
      JSONSerialization.jsonObject(with: json(named: "session")) as? [String: Any])
    session["token_type"] = nil

    let error = try #require(throws: AuthError.self) {
      try request.decode(ok, JSONSerialization.data(withJSONObject: session))
    }
    guard case .keyNotFound(let key, _) = error.underlyingError as? DecodingError else {
      Issue.record("Expected keyNotFound, got \(error)")
      return
    }
    #expect(key.stringValue == "tokenType")
  }

  @Test
  func verifyOTPDecodesASessionOrAnEmailChangeConfirmation() throws {
    let request = try api.verifyOTP(tokenHash: "h", type: .emailChange)

    let session = try request.decode(ok, json(named: "session"))
    #expect(session.session != nil)

    let pending = try request.decode(ok, json(named: "email-change-single-confirmation"))
    guard case .emailChangeConfirmationPending(let confirmation) = pending else {
      Issue.record("Expected .emailChangeConfirmationPending, got \(pending)")
      return
    }
    #expect(confirmation.code == "200")
  }

  @Test
  func oauthAuthorizationDetailsDecodesDetailsOrARedirect() throws {
    let request = api.oauthAuthorizationDetails(id: "abc", accessToken: "token")

    let details = try request.decode(
      ok,
      Data(
        """
        {
          "authorization_id": "abc",
          "redirect_uri": "https://example.com/callback",
          "client": {"id": "\(id)", "name": "Client"},
          "user": {"id": "\(id)", "email": "a@b.c"},
          "scope": "email"
        }
        """.utf8)
    )
    guard case .details(let value) = details else {
      Issue.record("Expected .details, got \(details)")
      return
    }
    #expect(value.authorizationId == "abc")

    let redirect = try request.decode(
      ok, Data(#"{"redirect_url":"https://example.com/callback?code=1"}"#.utf8))
    guard case .redirect(let value) = redirect else {
      Issue.record("Expected .redirect, got \(redirect)")
      return
    }
    #expect(value.redirectURL == URL(string: "https://example.com/callback?code=1"))
  }

  private let ok = HTTPTypes.HTTPResponse(status: .ok)

  private func query<Response>(_ request: AuthRequest<Response>) -> [String: String] {
    let items = URLComponents(string: request.head.path ?? "")?.queryItems ?? []
    return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
  }

  private func body<Response>(_ request: AuthRequest<Response>) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: #require(request.body))
  }
}
