//
//  RequestsTests.swift
//
//
//  Created by Guilherme Souza on 07/10/23.
//

import Foundation
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
      try await sut.signUp(
        email: "example@mail.com",
        password: "the.pass",
        data: ["custom_key": .string("custom_value")],
        redirectTo: URL(string: "https://supabase.com"),
        captchaToken: "dummy-captcha"
      )
    }
  }

  @Test
  func signUpWithPhoneAndPassword() async {
    let sut = makeSUT()

    await assert {
      try await sut.signUp(
        phone: "+1 202-918-2132",
        password: "the.pass",
        data: ["custom_key": .string("custom_value")],
        captchaToken: "dummy-captcha"
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
      try await sut.signInWithIdToken(
        credentials: OpenIDConnectCredentials(
          provider: .apple,
          idToken: "id-token",
          accessToken: "access-token",
          nonce: "nonce",
          gotrueMetaSecurity: AuthMetaSecurity(
            captchaToken: "captcha-token"
          )
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
        redirectTo: URL(string: "https://supabase.com"),
        shouldCreateUser: true,
        data: ["custom_key": .string("custom_value")],
        captchaToken: "dummy-captcha"
      )
    }
  }

  @Test
  func signInWithOTPUsingPhone() async {
    let sut = makeSUT()

    await assert {
      try await sut.signInWithOTP(
        phone: "+1 202-918-2132",
        shouldCreateUser: true,
        data: ["custom_key": .string("custom_value")],
        captchaToken: "dummy-captcha"
      )
    }
  }

  @Test
  func getOAuthSignInURL() async throws {
    let sut = makeSUT()
    let url = try sut.getOAuthSignInURL(
      provider: .github, scopes: "read,write",
      redirectTo: URL(string: "https://dummy-url.com/redirect")!,
      queryParams: [("extra_key", "extra_value")]
    )
    #expect(
      url
        == URL(
          string:
            "http://localhost:54321/auth/v1/authorize?provider=github&scopes=read,write&redirect_to=https://dummy-url.com/redirect&extra_key=extra_value"
        )!
    )
  }

  @Test
  func refreshSession() async {
    let sut = makeSUT()
    await assert {
      try await sut.refreshSession(refreshToken: "refresh-token")
    }
  }

  #if !os(Linux) && !os(Windows) && !os(Android)
    @Test
    func sessionFromURL() async throws {
      let sut = makeSUT(fetch: { request in
        let authorizationHeader = request.allHTTPHeaderFields?["Authorization"]
        #expect(authorizationHeader == "bearer accesstoken")
        return (json(named: "user"), HTTPURLResponse.stub())
      })

      let currentDate = Date()

      Dependencies[sut.clientID].date = { currentDate }

      let url = URL(
        string:
          "https://dummy-url.com/callback#access_token=accesstoken&expires_in=60&refresh_token=refreshtoken&token_type=bearer"
      )!

      let session = try await sut.session(from: url)
      let expectedSession = Session(
        accessToken: "accesstoken",
        tokenType: "bearer",
        expiresIn: 60,
        expiresAt: currentDate.addingTimeInterval(60).timeIntervalSince1970,
        refreshToken: "refreshtoken",
        user: User(fromMockNamed: "user")
      )
      #expect(session == expectedSession)
    }
  #endif

  @Test
  func sessionFromURLWithMissingComponent() async {
    let sut = makeSUT()

    let url = URL(
      string:
        "https://dummy-url.com/callback#access_token=accesstoken&expires_in=60&refresh_token=refreshtoken"
    )!

    do {
      _ = try await sut.session(from: url)
    } catch {
      assertInlineSnapshot(of: error, as: .dump) {
        """
        ▿ AuthError
          ▿ implicitGrantRedirect: (1 element)
            - message: "No session defined in URL"

        """
      }
    }
  }

  @Test
  func setSessionWithAFutureExpirationDate() async throws {
    let sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjo0ODUyMTYzNTkzLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.UiEhoahP9GNrBKw_OHBWyqYudtoIlZGkrjs7Qa8hU7I"

    await assert {
      try await sut.setSession(accessToken: accessToken, refreshToken: "dummy-refresh-token")
    }
  }

  @Test
  func setSessionWithAExpiredToken() async throws {
    let sut = makeSUT()

    let accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjoxNjQ4NjQwMDIxLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.CGr5zNE5Yltlbn_3Ms2cjSLs_AW9RKM3lxh7cTQrg0w"

    await assert {
      try await sut.setSession(accessToken: accessToken, refreshToken: "dummy-refresh-token")
    }
  }

  @Test
  func signOut() async throws {
    let sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    await assert {
      try await sut.signOut()
    }
  }

  @Test
  func signOutWithLocalScope() async throws {
    let sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    await assert {
      try await sut.signOut(scope: .local)
    }
  }

  @Test
  func signOutWithOthersScope() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

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
        type: .magiclink,
        redirectTo: URL(string: "https://supabase.com"),
        captchaToken: "captcha-token"
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
        type: .sms,
        captchaToken: "captcha-token"
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

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    await assert {
      try await sut.update(
        user: UserAttributes(
          email: "example@mail.com",
          phone: "+1 202-918-2132",
          password: "another.pass",
          nonce: "abcdef",
          emailChangeToken: "123456",
          data: ["custom_key": .string("custom_value")]
        )
      )
    }
  }

  @Test
  func resetPasswordForEmail() async {
    let sut = makeSUT()
    await assert {
      try await sut.resetPasswordForEmail(
        "example@mail.com",
        redirectTo: URL(string: "https://supabase.com"),
        captchaToken: "captcha-token"
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
        emailRedirectTo: URL(string: "https://supabase.com"),
        captchaToken: "captcha-token"
      )
    }
  }

  @Test
  func resendPhone() async {
    let sut = makeSUT()

    await assert {
      try await sut.resend(
        phone: "+1 202-918-2132",
        type: .phoneChange,
        captchaToken: "captcha-token"
      )
    }
  }

  @Test
  func deleteUser() async {
    let sut = makeSUT()

    let id = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
    await assert {
      try await sut.admin.deleteUser(id: id)
    }
  }

  @Test
  func reauthenticate() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    await assert {
      try await sut.reauthenticate()
    }
  }

  @Test
  func unlinkIdentity() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    await assert {
      try await sut.unlinkIdentity(
        UserIdentity(
          id: "5923044",
          identityId: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
          userId: UUID(),
          identityData: [:],
          provider: "email",
          createdAt: Date(),
          lastSignInAt: Date(),
          updatedAt: Date()
        )
      )
    }
  }

  @Test
  func signInWithSSOUsingDomain() async {
    let sut = makeSUT()

    await assert {
      _ = try await sut.signInWithSSO(
        domain: "supabase.com",
        redirectTo: URL(string: "https://supabase.com"),
        captchaToken: "captcha-token"
      )
    }
  }

  @Test
  func signInWithSSOUsingProviderId() async {
    let sut = makeSUT()

    await assert {
      _ = try await sut.signInWithSSO(
        providerId: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
        redirectTo: URL(string: "https://supabase.com"),
        captchaToken: "captcha-token"
      )
    }
  }

  @Test
  func signInAnonymously() async {
    let sut = makeSUT()

    await assert {
      try await sut.signInAnonymously(
        data: ["custom_key": .string("custom_value")],
        captchaToken: "captcha-token"
      )
    }
  }

  @Test
  func getLinkIdentityURL() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    await assert {
      _ = try await sut.getLinkIdentityURL(
        provider: .github,
        scopes: "user:email",
        redirectTo: URL(string: "https://supabase.com"),
        queryParams: [("extra_key", "extra_value")]
      )
    }
  }

  @Test
  func mfaEnrollLegacy() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    await assert {
      _ = try await sut.mfa.enroll(
        params: MFAEnrollParams(issuer: "supabase.com", friendlyName: "test"))
    }
  }

  @Test
  func mfaEnrollTotp() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    await assert {
      _ = try await sut.mfa.enroll(params: .totp(issuer: "supabase.com", friendlyName: "test"))
    }
  }

  @Test
  func mfaEnrollPhone() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    await assert {
      _ = try await sut.mfa.enroll(params: .phone(friendlyName: "test", phone: "+1 202-918-2132"))
    }
  }

  @Test
  func mfaChallenge() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    await assert {
      _ = try await sut.mfa.challenge(params: .init(factorId: "123"))
    }
  }

  @Test
  func mfaChallengePhone() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    await assert {
      _ = try await sut.mfa.challenge(params: .init(factorId: "123", channel: .whatsapp))
    }
  }

  @Test
  func mfaVerify() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    await assert {
      _ = try await sut.mfa.verify(
        params: .init(factorId: "123", challengeId: "123", code: "123456"))
    }
  }

  @Test
  func mfaUnenroll() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    await assert {
      _ = try await sut.mfa.unenroll(params: .init(factorId: "123"))
    }
  }

  @Test
  func mfaEnrollWebAuthn() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    await assert {
      _ = try await sut.mfa.enroll(params: .webAuthn(friendlyName: "My Passkey"))
    }
  }

  @Test
  func mfaChallengeWebAuthn() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    await assert {
      _ = try await sut.mfa.challenge(
        params: .init(
          factorId: "123",
          webAuthn: .init(rpId: "example.com", rpOrigins: ["https://example.com"])
        )
      )
    }
  }

  @Test
  func mfaVerifyWebAuthn() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    // The credential response carries W3C camelCase keys (e.g. `clientDataJSON`)
    // that MUST survive encoding untouched by the snake_case strategy.
    await assert {
      _ = try await sut.mfa.verify(
        params: .init(
          factorId: "123",
          challengeId: "456",
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
      )
    }
  }

  @Test
  func getPasskeyRegistrationOptions() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    await assert {
      _ = try await sut.getPasskeyRegistrationOptions()
    }
  }

  @Test
  func verifyPasskeyRegistration() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    await assert {
      _ = try await sut.verifyPasskeyRegistration(
        challengeId: "challenge-1",
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
  func getPasskeyAuthenticationOptions() async throws {
    let sut = makeSUT()

    // No session stored: passkey authentication options must not require auth.
    await assert {
      _ = try await sut.getPasskeyAuthenticationOptions()
    }
  }

  @Test
  func verifyPasskeyAuthentication() async throws {
    let sut = makeSUT()

    await assert {
      _ = try await sut.verifyPasskeyAuthentication(
        challengeId: "challenge-1",
        credentialResponse: [
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

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    await assert {
      _ = try await sut.listPasskeys()
    }
  }

  @Test
  func renamePasskey() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    await assert {
      _ = try await sut.renamePasskey(id: "passkey-1", friendlyName: "Renamed Passkey")
    }
  }

  @Test
  func deletePasskey() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    await assert {
      try await sut.deletePasskey(id: "passkey-1")
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

  private func makeSUT(
    record: Bool = false,
    flowType: AuthFlowType = .implicit,
    fetch: AuthClient.FetchHandler? = nil,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
  ) -> AuthClient {
    let encoder = AuthClient.Configuration.jsonEncoder
    encoder.outputFormatting = .sortedKeys

    let configuration = AuthClient.Configuration(
      url: clientURL,
      headers: ["Apikey": "dummy.api.key", "X-Client-Info": "gotrue-swift/x.y.z"],
      flowType: flowType,
      localStorage: InMemoryLocalStorage(),
      logger: nil,
      encoder: encoder,
      fetch: { request in
        await MainActor.run {
          assertSnapshot(
            of: request, as: ._curl, record: record, file: file, testName: testName, line: line
          )
        }

        if let fetch {
          return try await fetch(request)
        }

        throw UnimplementedError()
      }
    )

    return AuthClient(configuration: configuration)
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
