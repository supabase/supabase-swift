//
//  RequestsTests.swift
//
//
//  Created by Guilherme Souza on 07/10/23.
//

import Foundation
import HTTPTypesFoundation
import Helpers
import InlineSnapshotTesting
import SnapshotTesting
import TestHelpers
import Testing

@_spi(Experimental) @testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct UnimplementedError: Error {}

@Suite
struct RequestsTests {
  @Test
  func signUpWithEmailAndPassword() async {
    let sut = makeSUT()

    await assert {
      _ = try await sut.signUp(
        email: "example@mail.com",
        password: "the.pass",
        options: SignUpOptions(
          userMetadata: ["custom_key": .string("custom_value")],
          redirectTo: URL(string: "https://supabase.com"),
          captchaToken: "dummy-captcha"
        )
      )
    }
  }

  @Test
  func signUpWithPhoneAndPassword() async {
    let sut = makeSUT()

    await assert {
      _ = try await sut.signUp(
        phone: "+1 202-918-2132",
        password: "the.pass",
        options: SignUpOptions(
          userMetadata: ["custom_key": .string("custom_value")],
          captchaToken: "dummy-captcha"
        )
      )
    }
  }

  @Test
  func signInWithEmailAndPassword() async {
    let sut = makeSUT()

    await assert {
      try await sut.signIn(
        email: "example@mail.com",
        password: "the.pass",
        captchaToken: "dummy-captcha"
      )
    }
  }

  @Test
  func signInWithPhoneAndPassword() async {
    let sut = makeSUT()

    await assert {
      try await sut.signIn(
        phone: "+1 202-918-2132",
        password: "the.pass",
        captchaToken: "dummy-captcha"
      )
    }
  }

  @Test
  func signInWithIdToken() async {
    let sut = makeSUT()

    await assert {
      try await sut.signInWithIDToken(
        IDTokenCredentials(
          provider: .apple,
          idToken: "id-token",
          nonce: "nonce",
          accessToken: "access-token",
          captchaToken: "captcha-token"
        )
      )
    }
  }

  @Test
  func signInWithOTPUsingEmail() async {
    let sut = makeSUT()

    await assert {
      try await sut.signInWithOTP(
        email: "example@mail.com",
        options: EmailOTPOptions(
          shouldCreateUser: true,
          userMetadata: ["custom_key": .string("custom_value")],
          redirectTo: URL(string: "https://supabase.com"),
          captchaToken: "dummy-captcha"
        )
      )
    }
  }

  @Test
  func signInWithOTPUsingPhone() async {
    let sut = makeSUT()

    await assert {
      _ = try await sut.signInWithOTP(
        phone: "+1 202-918-2132",
        options: PhoneOTPOptions(
          shouldCreateUser: true,
          userMetadata: ["custom_key": .string("custom_value")],
          captchaToken: "dummy-captcha"
        )
      )
    }
  }

  @Test
  func oauthSignInURL() async throws {
    let sut = makeSUT()
    let flow = try await sut.oauthSignInURL(
      .github,
      options: OAuthOptions(
        scopes: ["read", "write"],
        redirectTo: URL(string: "https://dummy-url.com/redirect")!,
        queryItems: [URLQueryItem(name: "extra_key", value: "extra_value")]
      )
    )
    #expect(
      flow.url
        == URL(
          string:
            "http://localhost:54321/auth/v1/authorize?provider=github&scopes=read%20write&redirect_to=https://dummy-url.com/redirect&code_challenge=challenge&code_challenge_method=s256&extra_key=extra_value"
        )!
    )
  }

  @Test
  func refreshSession() async {
    let sut = makeSUT()
    var session = Session.valid
    session.refreshToken = "refresh-token"
    try? await sut.seedSession(session)
    await assert {
      try await sut.refreshSession()
    }
  }

  #if !os(Linux) && !os(Windows) && !os(Android)
    @Test
    func sessionFromURL() async throws {
      let currentDate = Date()

      let sut = makeSUT(
        fetch: { request in
          let authorizationHeader = request.allHTTPHeaderFields?["Authorization"]
          #expect(authorizationHeader == "bearer accesstoken")
          return (json(named: "user"), HTTPURLResponse.stub())
        },
        date: { currentDate }
      )

      let url = URL(
        string:
          "https://dummy-url.com/callback#access_token=accesstoken&expires_in=60&refresh_token=refreshtoken&token_type=bearer"
      )!

      let result = try await sut.handleRedirect(url)
      let expectedSession = Session(
        accessToken: "accesstoken",
        tokenType: "bearer",
        expiresIn: .seconds(60),
        expiresAt: currentDate.addingTimeInterval(60),
        receivedAt: currentDate,
        refreshToken: "refreshtoken",
        user: User(fromMockNamed: "user")
      )
      #expect(result == .signedIn(expectedSession, verification: nil))
    }
  #endif

  @Test
  func sessionFromURLWithMissingComponent() async {
    let sut = makeSUT()

    let url = URL(
      string:
        "https://dummy-url.com/callback#access_token=accesstoken&expires_in=60&refresh_token=refreshtoken"
    )!

    let error = await #expect(throws: AuthError.self) {
      try await sut.handleRedirect(url)
    }
    #expect(error?.kind == .oauthFlowFailed)
  }

  @Test
  func importSessionWithAFutureExpirationDate() async throws {
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    let accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjo0ODUyMTYzNTkzLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.UiEhoahP9GNrBKw_OHBWyqYudtoIlZGkrjs7Qa8hU7I"

    await assert {
      try await sut.importSession(accessToken: accessToken, refreshToken: "dummy-refresh-token")
    }
  }

  @Test
  func importSessionWithAnExpiredToken() async throws {
    let sut = makeSUT()

    let accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjoxNjQ4NjQwMDIxLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.CGr5zNE5Yltlbn_3Ms2cjSLs_AW9RKM3lxh7cTQrg0w"

    await assert {
      try await sut.importSession(accessToken: accessToken, refreshToken: "dummy-refresh-token")
    }
  }

  @Test
  func signOutWithGlobalScope() async throws {
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    await assert {
      try await sut.signOut(scope: .global)
    }
  }

  @Test
  func signOutWithLocalScope() async throws {
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    await assert {
      try await sut.signOut(scope: .local)
    }
  }

  @Test
  func signOutWithOthersScope() async throws {
    let sut = makeSUT()

    try await sut.seedSession(.valid)

    await assert {
      try await sut.signOut(scope: .others)
    }
  }

  @Test
  func verifyOTPUsingEmail() async {
    let sut = makeSUT()

    await assert {
      try await sut.verifyOTP(
        email: "example@mail.com",
        token: "123456",
        type: .magiclink
      )
    }
  }

  @Test
  func verifyOTPUsingPhone() async {
    let sut = makeSUT()

    await assert {
      try await sut.verifyOTP(
        phone: "+1 202-918-2132",
        token: "123456",
        type: .sms
      )
    }
  }

  @Test
  func verifyOTPUsingTokenHash() async {
    let sut = makeSUT()

    await assert {
      try await sut.verifyOTP(
        tokenHash: "abc-def",
        type: .email
      )
    }
  }

  @Test
  func updateUser() async throws {
    let sut = makeSUT()

    try await sut.seedSession(.valid)

    await assert {
      try await sut.updateUser(
        UserAttributes(
          email: "example@mail.com",
          phone: "+1 202-918-2132",
          password: "another.pass",
          nonce: "abcdef",
          userMetadata: ["custom_key": .string("custom_value")]
        )
      )
    }
  }

  @Test
  func updateUserWithCurrentPassword() async throws {
    let sut = makeSUT()

    try await sut.seedSession(.valid)

    await assert {
      try await sut.updateUser(
        UserAttributes(password: "new-pass", currentPassword: "old-pass")
      )
    }
  }

  @Test
  func resetPassword() async {
    let sut = makeSUT()
    await assert {
      try await sut.resetPassword(
        email: "example@mail.com",
        options: .init(
          redirectTo: URL(string: "https://supabase.com"), captchaToken: "captcha-token")
      )
    }
  }

  @Test
  func resendEmail() async {
    let sut = makeSUT()

    await assert {
      try await sut.resend(
        email: "example@mail.com",
        type: .emailChange,
        options: .init(
          redirectTo: URL(string: "https://supabase.com"), captchaToken: "captcha-token")
      )
    }
  }

  @Test
  func resendPhone() async {
    let sut = makeSUT()

    await assert {
      _ = try await sut.resend(
        phone: "+1 202-918-2132",
        type: .phoneChange,
        options: .init(captchaToken: "captcha-token")
      )
    }
  }

  @Test
  func deleteUser() async {
    let sut = makeAdminSUT()

    let id = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
    await assert {
      try await sut.deleteUser(id: id)
    }
  }

  @Test
  func adminListPasskeys() async throws {
    let sut = makeAdminSUT()

    let userId = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
    await assert {
      _ = try await sut.passkeys.list(forUser: userId)
    }
  }

  @Test
  func adminDeletePasskey() async throws {
    let sut = makeAdminSUT()

    let userId = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
    let passkeyId = UUID(uuidString: "859F402D-B3DE-4105-A1B9-932836D9193B")!
    await assert {
      try await sut.passkeys.delete(id: passkeyId, forUser: userId)
    }
  }

  @Test
  func reauthenticate() async throws {
    let sut = makeSUT()

    try await sut.seedSession(.valid)

    await assert {
      try await sut.reauthenticate()
    }
  }

  @Test
  func unlinkIdentity() async throws {
    let sut = makeSUT()

    try await sut.seedSession(.valid)

    await assert {
      try await sut.unlinkIdentity(
        UserIdentity(
          id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
          providerUserID: "5923044",
          userID: UUID(),
          provider: .email,
          createdAt: Date(),
          lastSignInAt: Date(),
          updatedAt: Date()
        )
      )
    }
  }

  @Test
  func ssoSignInURLUsingDomain() async {
    let sut = makeSUT()

    await assert {
      _ = try await sut.ssoSignInURL(
        .domain("supabase.com"),
        options: SSOOptions(
          redirectTo: URL(string: "https://supabase.com"),
          captchaToken: "captcha-token"
        )
      )
    }
  }

  @Test
  func ssoSignInURLUsingProviderID() async {
    let sut = makeSUT()

    await assert {
      _ = try await sut.ssoSignInURL(
        .providerID(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!),
        options: SSOOptions(
          redirectTo: URL(string: "https://supabase.com"),
          captchaToken: "captcha-token"
        )
      )
    }
  }

  @Test
  func signInAnonymously() async {
    let sut = makeSUT()

    await assert {
      try await sut.signInAnonymously(
        userMetadata: ["custom_key": .string("custom_value")],
        captchaToken: "captcha-token"
      )
    }
  }

  @Test
  func linkIdentityURL() async throws {
    let sut = makeSUT()

    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.linkIdentityURL(
        .github,
        options: OAuthOptions(
          scopes: ["user:email"],
          redirectTo: URL(string: "https://supabase.com"),
          queryItems: [URLQueryItem(name: "extra_key", value: "extra_value")]
        )
      )
    }
  }

  @Test
  func mfaEnrollTotp() async throws {
    let sut = makeSUT()

    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.mfa.enrollTOTP(issuer: "supabase.com", friendlyName: "test")
    }
  }

  @Test
  func mfaEnrollPhone() async throws {
    let sut = makeSUT()

    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.mfa.enrollPhone("+1 202-918-2132", friendlyName: "test")
    }
  }

  @Test
  func mfaChallenge() async throws {
    let sut = makeSUT()

    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.mfa.challenge(
        factorID: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!)
    }
  }

  @Test
  func mfaChallengePhone() async throws {
    let sut = makeSUT()

    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.mfa.challenge(
        factorID: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!, channel: .whatsapp)
    }
  }

  @Test
  func mfaVerify() async throws {
    let sut = makeSUT()

    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.mfa.verify(
        factorID: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
        challengeID: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
        code: "123456")
    }
  }

  @Test
  func mfaUnenroll() async throws {
    let sut = makeSUT()

    try await sut.seedSession(.valid)

    await assert {
      try await sut.mfa.unenroll(
        factorID: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!)
    }
  }

  @Test
  func mfaEnrollWebAuthn() async throws {
    let sut = makeSUT()

    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.mfa.enrollWebAuthnFactor(friendlyName: "My Passkey")
    }
  }

  @Test
  func mfaChallengeWebAuthn() async throws {
    let sut = makeSUT()

    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.mfa.challenge(
        factorID: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
        webAuthn: .init(rpId: "example.com", rpOrigins: ["https://example.com"])
      )
    }
  }

  @Test
  func mfaVerifyWebAuthn() async throws {
    let sut = makeSUT()

    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.mfa.verify(
        factorID: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
        challengeID: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
        type: .create,
        credentialResponse: [
          "id": "credential-id",
          "rawId": "cmF3LWNyZWRlbnRpYWwtaWQ",
          "type": "public-key",
          "response": [
            "clientDataJSON": "Y2xpZW50LWRhdGE",
            "attestationObject": "YXR0ZXN0YXRpb24tb2JqZWN0",
          ],
        ]
      )
    }
  }

  @Test
  func passkeyRegistrationOptions() async throws {
    let sut = makeSUT()

    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.passkeys.registrationOptions()
    }
  }

  @Test
  func verifyPasskeyRegistration() async throws {
    let sut = makeSUT()

    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.passkeys.verifyRegistration(
        challengeID: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
        credential: [
          "id": "credential-id",
          "rawId": "cmF3LWNyZWRlbnRpYWwtaWQ",
          "type": "public-key",
          "response": [
            "clientDataJSON": "Y2xpZW50LWRhdGE",
            "attestationObject": "YXR0ZXN0YXRpb24tb2JqZWN0",
          ],
        ]
      )
    }
  }

  @Test
  func passkeyAuthenticationOptions() async throws {
    let sut = makeSUT()

    await assert {
      _ = try await sut.passkeys.authenticationOptions()
    }
  }

  @Test
  func verifyPasskeyAuthentication() async throws {
    let sut = makeSUT()

    await assert {
      _ = try await sut.passkeys.verifyAuthentication(
        challengeID: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
        credential: [
          "id": "credential-id",
          "rawId": "cmF3LWNyZWRlbnRpYWwtaWQ",
          "type": "public-key",
          "response": [
            "clientDataJSON": "Y2xpZW50LWRhdGE",
            "authenticatorData": "YXV0aGVudGljYXRvci1kYXRh",
            "signature": "c2lnbmF0dXJl",
            "userHandle": "dXNlci1oYW5kbGU",
          ],
        ]
      )
    }
  }

  @Test
  func listPasskeys() async throws {
    let sut = makeSUT()

    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.passkeys.list()
    }
  }

  @Test
  func renamePasskey() async throws {
    let sut = makeSUT()

    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.passkeys.rename(
        id: UUID(uuidString: "859F402D-B3DE-4105-A1B9-932836D9193B")!,
        friendlyName: "Renamed Passkey"
      )
    }
  }

  @Test
  func deletePasskey() async throws {
    let sut = makeSUT()

    try await sut.seedSession(.valid)

    await assert {
      try await sut.passkeys.delete(id: UUID(uuidString: "859F402D-B3DE-4105-A1B9-932836D9193B")!)
    }
  }

  @Test
  func signInWithWeb3() async {
    let sut = makeSUT()

    await assert {
      try await sut.signInWithWeb3(
        Web3Credentials(
          chain: .ethereum,
          message: "example.com wants you to sign in",
          // cspell:ignore xsignature
          signature: "0xsignature",
          captchaToken: "captcha-token"
        )
      )
    }
  }

  @Test
  func exchangeCodeForSession() async {
    let sut = makeSUT()

    await assert {
      _ = try await sut.oauthSignInURL(.github)
      try await sut.exchangeCodeForSession("auth-code")
    }
  }

  @Test
  func userWithJWT() async {
    let sut = makeSUT()

    await assert {
      _ = try await sut.user(jwt: "custom-jwt")
    }
  }

  @Test
  func userWithStoredSession() async throws {
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.user()
    }
  }

  @Test
  func linkIdentityWithIdToken() async throws {
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    await assert {
      try await sut.linkIdentity(
        idToken: IDTokenCredentials(
          provider: .google,
          idToken: "id-token",
          nonce: "nonce"
        )
      )
    }
  }

  @Test
  func fetchJWKS() async {
    let sut = makeSUT()
    // RS256 header with a key id, so the client fetches the key set.
    let jwt =
      "eyJhbGciOiJSUzI1NiIsImtpZCI6InJlcXVlc3RzLXRlc3RzLWtleSJ9.eyJzdWIiOiJyZXF1ZXN0cy10ZXN0cyIsImV4cCI6NDg1MjE2MzU5M30.c2ln"

    await assert {
      _ = try await sut.claims(jwt: jwt)
    }
  }

  @Test
  func recoveryCodesStatus() async throws {
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.mfa.recoveryCodes.status()
    }
  }

  @Test
  func recoveryCodesGenerate() async throws {
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.mfa.recoveryCodes.generate(friendlyName: "Backup codes")
    }
  }

  @Test
  func recoveryCodesVerify() async throws {
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    await assert {
      try await sut.mfa.recoveryCodes.verify(code: "K4M9-X7QP-2AB8-HT3Z")
    }
  }

  @Test
  func recoveryCodesRegenerate() async throws {
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.mfa.recoveryCodes.regenerate()
    }
  }

  @Test
  func recoveryCodesUnenroll() async throws {
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    await assert {
      try await sut.mfa.recoveryCodes.unenroll()
    }
  }

  @Test
  func oauthAuthorizationDetails() async throws {
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.oauthServer.authorizationDetails(id: "authorization-1")
    }
  }

  @Test
  func oauthApproveAuthorization() async throws {
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.oauthServer.approveAuthorization(id: "authorization-1")
    }
  }

  @Test
  func oauthDenyAuthorization() async throws {
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.oauthServer.denyAuthorization(id: "authorization-1")
    }
  }

  @Test
  func oauthListGrants() async throws {
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.oauthServer.listGrants()
    }
  }

  @Test
  func oauthRevokeGrant() async throws {
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    await assert {
      try await sut.oauthServer.revokeGrant(
        id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!)
    }
  }

  @Test
  func adminGetUser() async {
    let sut = makeAdminSUT()

    await assert {
      _ = try await sut.user(id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!)
    }
  }

  @Test
  func adminUpdateUser() async {
    let sut = makeAdminSUT()

    await assert {
      try await sut.updateUser(
        id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
        attributes: AdminUserAttributes(banDuration: .seconds(86_400), email: "new@mail.com")
      )
    }
  }

  @Test
  func adminCreateUser() async {
    let sut = makeAdminSUT()

    await assert {
      try await sut.createUser(
        AdminUserAttributes(
          email: "example@mail.com", confirmsEmail: true, password: "the.pass")
      )
    }
  }

  @Test
  func adminInviteUser() async {
    let sut = makeAdminSUT()

    await assert {
      try await sut.inviteUser(
        email: "example@mail.com",
        userMetadata: ["custom_key": .string("custom_value")],
        redirectTo: URL(string: "https://supabase.com")
      )
    }
  }

  @Test
  func adminSignOut() async {
    let sut = makeAdminSUT()

    await assert {
      try await sut.signOut(jwt: "user-jwt", scope: .others)
    }
  }

  @Test
  func adminListUsers() async {
    let sut = makeAdminSUT()

    await assert {
      _ = try await sut.listUsers(page: 2, perPage: 10)
    }
  }

  @Test
  func adminGenerateLink() async {
    let sut = makeAdminSUT()

    await assert {
      _ = try await sut.generateLink(
        .magicLink(
          email: "example@mail.com", redirectTo: URL(string: "https://supabase.com"))
      )
    }
  }

  @Test
  func adminListFactors() async {
    let sut = makeAdminSUT()

    await assert {
      _ = try await sut.mfa.listFactors(
        forUser: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!)
    }
  }

  @Test
  func adminDeleteFactor() async {
    let sut = makeAdminSUT()

    await assert {
      try await sut.mfa.deleteFactor(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
        forUser: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
      )
    }
  }

  @Test
  func adminListOAuthClients() async {
    let sut = makeAdminSUT()

    await assert {
      _ = try await sut.oauth.listClients(params: PageParams(page: 1, perPage: 5))
    }
  }

  @Test
  func adminCreateOAuthClient() async {
    let sut = makeAdminSUT()

    await assert {
      try await sut.oauth.createClient(
        params: CreateOAuthClientParams(
          clientName: "Example", redirectUris: ["https://example.com/callback"])
      )
    }
  }

  @Test
  func adminGetOAuthClient() async {
    let sut = makeAdminSUT()

    await assert {
      _ = try await sut.oauth.client(
        id: UUID(uuidString: "859F402D-B3DE-4105-A1B9-932836D9193B")!)
    }
  }

  @Test
  func adminUpdateOAuthClient() async {
    let sut = makeAdminSUT()

    await assert {
      _ = try await sut.oauth.updateClient(
        id: UUID(uuidString: "859F402D-B3DE-4105-A1B9-932836D9193B")!,
        params: UpdateOAuthClientParams(clientName: "Renamed")
      )
    }
  }

  @Test
  func adminDeleteOAuthClient() async {
    let sut = makeAdminSUT()

    await assert {
      try await sut.oauth.deleteClient(
        id: UUID(uuidString: "859F402D-B3DE-4105-A1B9-932836D9193B")!)
    }
  }

  @Test
  func adminRegenerateOAuthClientSecret() async {
    let sut = makeAdminSUT()

    await assert {
      try await sut.oauth.regenerateClientSecret(
        id: UUID(uuidString: "859F402D-B3DE-4105-A1B9-932836D9193B")!)
    }
  }

  @Test
  func adminLiftBan() async {
    let sut = makeAdminSUT()

    await assert {
      try await sut.updateUser(
        id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
        attributes: AdminUserAttributes(banDuration: .zero)
      )
    }
  }

  @Test
  func adminSoftDeleteUser() async {
    let sut = makeAdminSUT()

    await assert {
      try await sut.deleteUser(
        id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!, softDelete: true)
    }
  }

  @Test
  func adminListCustomProviders() async {
    let sut = makeAdminSUT()

    await assert {
      _ = try await sut.customProviders.list(type: .oidc)
    }
  }

  @Test
  func adminCreateCustomProvider() async {
    let sut = makeAdminSUT()

    var params = CreateCustomProviderParams.oauth2(
      identifier: "custom:acme",
      name: "Acme",
      clientID: "client-id",
      clientSecret: "client-secret",
      authorizationURL: URL(string: "https://acme.example.com/authorize")!,
      tokenURL: URL(string: "https://acme.example.com/token")!,
      userinfoURL: URL(string: "https://acme.example.com/userinfo")!
    )
    params.scopes = ["openid", "email"]
    params.customClaimsAllowlist = ["groups"]

    await assert {
      try await sut.customProviders.create(params)
    }
  }

  @Test
  func adminGetCustomProvider() async {
    let sut = makeAdminSUT()

    await assert {
      _ = try await sut.customProviders.provider(identifier: "custom:acme")
    }
  }

  @Test
  func adminUpdateCustomProvider() async {
    let sut = makeAdminSUT()

    await assert {
      try await sut.customProviders.update(
        identifier: "custom:acme",
        params: UpdateCustomProviderParams(name: "Acme Inc.", customClaimsAllowlist: [])
      )
    }
  }

  @Test
  func adminDeleteCustomProvider() async {
    let sut = makeAdminSUT()

    await assert {
      try await sut.customProviders.delete(identifier: "custom:acme")
    }
  }

  private func assert(_ block: () async throws -> Void) async {
    do {
      try await block()
    } catch is UnimplementedError {
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  private func makeAdminSUT(
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
  ) -> AuthAdminClient {
    AuthAdminClient(
      url: clientURL,
      secretKey: "dummy.secret.key",
      http: .init(
        transport: snapshotTransport(
          record: false, fetch: nil, file: file, testName: testName, line: line))
    )
  }

  private func snapshotTransport(
    record: Bool,
    fetch: (@Sendable (URLRequest) async throws -> (Data, URLResponse))?,
    file: StaticString,
    testName: String,
    line: UInt
  ) -> ClosureTransport {
    ClosureTransport { request, body in
      guard var urlRequest = URLRequest(httpRequest: request) else { throw URLError(.badURL) }
      if let body { urlRequest.httpBody = try await Data(collecting: body, upTo: .max) }

      await MainActor.run {
        assertSnapshot(
          of: urlRequest, as: ._curl, record: record, file: file, testName: testName, line: line
        )
      }

      if let fetch {
        let (data, response) = try await fetch(urlRequest)
        guard let head = (response as? HTTPURLResponse)?.httpResponse else {
          throw URLError(.badServerResponse)
        }
        return (head, data.isEmpty ? nil : HTTPBody(data))
      }

      throw UnimplementedError()
    }
  }

  private func makeSUT(
    record: Bool = false,
    fetch: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = nil,
    date: @escaping @Sendable () -> Date = { Date() },
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
  ) -> AuthClient {
    let configuration = AuthClient.Configuration(
      url: clientURL,
      storageKey: uniqueStorageKey(),
      headers: HTTPFields(["Apikey": "dummy.api.key", "X-Client-Info": "gotrue-swift/x.y.z"]),
      storage: InMemoryTestStorage(),
      http: .init(
        transport: snapshotTransport(
          record: record, fetch: fetch, file: file, testName: testName, line: line)),
      autoRefresh: .manual,
      now: date
    )

    let pkce = PKCE(
      generateCodeVerifier: { "verifier" },
      generateCodeChallenge: { _ in "challenge" }
    )
    return AuthClient(configuration: configuration, pkce: pkce, platform: .live)
  }
}

extension HTTPURLResponse {
  fileprivate static func stub(code: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(
      url: clientURL,
      statusCode: code,
      httpVersion: nil,
      headerFields: nil
    )!
  }
}
