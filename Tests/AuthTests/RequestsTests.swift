//
//  RequestsTests.swift
//
//
//  Created by Guilherme Souza on 07/10/23.
//

import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@_spi(Experimental) @testable import Auth

struct UnimplementedError: Error {}

/// Pins the exact request of each call that no other Auth test snapshots. Every request fails
/// with `UnimplementedError`, so each test checks only what the client sends.
@Suite
struct RequestsTests {
  let transport = RecordingTransport { _, _ in throw UnimplementedError() }

  @Test
  func signInWithOTPUsingPhone() async throws {
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

    try transport.assertFirstRequestSnapshot(.post, "otp") {
      #"""
      curl \
      	--request POST \
      	--header "Apikey: dummy.api.key" \
      	--header "Content-Length: 156" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: gotrue-swift/x.y.z" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--data "{\"channel\":\"sms\",\"create_user\":true,\"data\":{\"custom_key\":\"custom_value\"},\"gotrue_meta_security\":{\"captcha_token\":\"dummy-captcha\"},\"phone\":\"+1 202-918-2132\"}" \
      	"http://localhost:54321/auth/v1/otp"
      """#
    }
  }

  @Test
  func signInAnonymously() async throws {
    let sut = makeSUT()

    await assert {
      try await sut.signInAnonymously(
        userMetadata: ["custom_key": .string("custom_value")],
        captchaToken: "captcha-token"
      )
    }

    try transport.assertFirstRequestSnapshot(.post, "signup") {
      #"""
      curl \
      	--request POST \
      	--header "Apikey: dummy.api.key" \
      	--header "Content-Length: 95" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: gotrue-swift/x.y.z" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--data "{\"data\":{\"custom_key\":\"custom_value\"},\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"}}" \
      	"http://localhost:54321/auth/v1/signup"
      """#
    }
  }

  @Test
  func sessionFromURLWithMissingComponent() async {
    let sut = makeSUT(redirectTo: URL(string: "https://dummy-url.com/callback")!)

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
  func updateUserWithCurrentPassword() async throws {
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    await assert {
      try await sut.updateUser(
        UpdateUser(password: "new-pass", currentPassword: "old-pass")
      )
    }

    try transport.assertFirstRequestSnapshot(.put, "user") {
      #"""
      curl \
      	--request PUT \
      	--header "Apikey: dummy.api.key" \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 53" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: gotrue-swift/x.y.z" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--data "{\"current_password\":\"old-pass\",\"password\":\"new-pass\"}" \
      	"http://localhost:54321/auth/v1/user"
      """#
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

    try transport.assertFirstRequestSnapshot(.get, "user/identities/authorize") {
      #"""
      curl \
      	--header "Apikey: dummy.api.key" \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: gotrue-swift/x.y.z" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	"http://localhost:54321/auth/v1/user/identities/authorize?code_challenge=challenge&code_challenge_method=s256&extra_key=extra_value&provider=github&redirect_to=https://supabase.com&scopes=user:email&skip_http_redirect=true"
      """#
    }
  }

  @Test
  func userWithJWT() async throws {
    let sut = makeSUT()

    await assert {
      _ = try await sut.user(jwt: "custom-jwt")
    }

    try transport.assertFirstRequestSnapshot(.get, "user") {
      #"""
      curl \
      	--header "Apikey: dummy.api.key" \
      	--header "Authorization: Bearer custom-jwt" \
      	--header "X-Client-Info: gotrue-swift/x.y.z" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	"http://localhost:54321/auth/v1/user"
      """#
    }
  }

  @Test
  func userWithStoredSession() async throws {
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.user()
    }

    try transport.assertFirstRequestSnapshot(.get, "user") {
      #"""
      curl \
      	--header "Apikey: dummy.api.key" \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: gotrue-swift/x.y.z" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	"http://localhost:54321/auth/v1/user"
      """#
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

    try transport.assertFirstRequestSnapshot(
      .post, "factors/00000000-0000-0000-0000-000000000123/challenge"
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Apikey: dummy.api.key" \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 22" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: gotrue-swift/x.y.z" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--data "{\"channel\":\"whatsapp\"}" \
      	"http://localhost:54321/auth/v1/factors/00000000-0000-0000-0000-000000000123/challenge"
      """#
    }
  }

  @Test
  func mfaEnrollWebAuthn() async throws {
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.mfa.enrollWebAuthnFactor(friendlyName: "My Passkey")
    }

    try transport.assertFirstRequestSnapshot(.post, "factors") {
      #"""
      curl \
      	--request POST \
      	--header "Apikey: dummy.api.key" \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 55" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: gotrue-swift/x.y.z" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--data "{\"factor_type\":\"webauthn\",\"friendly_name\":\"My Passkey\"}" \
      	"http://localhost:54321/auth/v1/factors"
      """#
    }
  }

  @Test
  func mfaChallengeWebAuthn() async throws {
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.mfa.challenge(
        factorID: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
        webAuthn: .init(rpID: "example.com", rpOrigins: ["https://example.com"])
      )
    }

    try transport.assertFirstRequestSnapshot(
      .post, "factors/00000000-0000-0000-0000-000000000123/challenge"
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Apikey: dummy.api.key" \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 75" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: gotrue-swift/x.y.z" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--data "{\"webauthn\":{\"rp_id\":\"example.com\",\"rp_origins\":[\"https:\/\/example.com\"]}}" \
      	"http://localhost:54321/auth/v1/factors/00000000-0000-0000-0000-000000000123/challenge"
      """#
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
        credentialResponse: Self.credential
      )
    }

    try transport.assertFirstRequestSnapshot(
      .post, "factors/00000000-0000-0000-0000-000000000123/verify"
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Apikey: dummy.api.key" \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 329" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: gotrue-swift/x.y.z" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--data "{\"challenge_id\":\"E621E1F8-C36C-495A-93FC-0C247A3E6E5F\",\"factor_id\":\"00000000-0000-0000-0000-000000000123\",\"webauthn\":{\"credential_response\":{\"id\":\"credential-id\",\"rawId\":\"cmF3LWNyZWRlbnRpYWwtaWQ\",\"response\":{\"attestationObject\":\"YXR0ZXN0YXRpb24tb2JqZWN0\",\"clientDataJSON\":\"Y2xpZW50LWRhdGE\"},\"type\":\"public-key\"},\"type\":\"create\"}}" \
      	"http://localhost:54321/auth/v1/factors/00000000-0000-0000-0000-000000000123/verify"
      """#
    }
  }

  @Test
  func verifyPasskeyRegistration() async throws {
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    await assert {
      _ = try await sut.passkeys.verifyRegistration(
        challengeID: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
        credential: Self.credential
      )
    }

    try transport.assertFirstRequestSnapshot(.post, "passkeys/registration/verify") {
      #"""
      curl \
      	--request POST \
      	--header "Apikey: dummy.api.key" \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 240" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: gotrue-swift/x.y.z" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--data "{\"challenge_id\":\"E621E1F8-C36C-495A-93FC-0C247A3E6E5F\",\"credential\":{\"id\":\"credential-id\",\"rawId\":\"cmF3LWNyZWRlbnRpYWwtaWQ\",\"response\":{\"attestationObject\":\"YXR0ZXN0YXRpb24tb2JqZWN0\",\"clientDataJSON\":\"Y2xpZW50LWRhdGE\"},\"type\":\"public-key\"}}" \
      	"http://localhost:54321/auth/v1/passkeys/registration/verify"
      """#
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

    try transport.assertFirstRequestSnapshot(
      .patch, "passkeys/859F402D-B3DE-4105-A1B9-932836D9193B"
    ) {
      #"""
      curl \
      	--request PATCH \
      	--header "Apikey: dummy.api.key" \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 35" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: gotrue-swift/x.y.z" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--data "{\"friendly_name\":\"Renamed Passkey\"}" \
      	"http://localhost:54321/auth/v1/passkeys/859F402D-B3DE-4105-A1B9-932836D9193B"
      """#
    }
  }

  @Test
  func deletePasskey() async throws {
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    await assert {
      try await sut.passkeys.delete(id: UUID(uuidString: "859F402D-B3DE-4105-A1B9-932836D9193B")!)
    }

    try transport.assertFirstRequestSnapshot(
      .delete, "passkeys/859F402D-B3DE-4105-A1B9-932836D9193B"
    ) {
      #"""
      curl \
      	--request DELETE \
      	--header "Apikey: dummy.api.key" \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: gotrue-swift/x.y.z" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	"http://localhost:54321/auth/v1/passkeys/859F402D-B3DE-4105-A1B9-932836D9193B"
      """#
    }
  }

  @Test
  func adminUpdateUser() async throws {
    let sut = makeAdminSUT()

    await assert {
      try await sut.updateUser(
        id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
        AdminUpdateUser(email: "new@mail.com", banDuration: .seconds(86_400))
      )
    }

    try transport.assertFirstRequestSnapshot(
      .put, "admin/users/E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
    ) {
      #"""
      curl \
      	--request PUT \
      	--header "Authorization: Bearer dummy.secret.key" \
      	--header "Content-Length: 48" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: dummy.secret.key" \
      	--data "{\"ban_duration\":\"86400s\",\"email\":\"new@mail.com\"}" \
      	"http://localhost:54321/auth/v1/admin/users/E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
      """#
    }
  }

  @Test
  func adminLiftBan() async throws {
    let sut = makeAdminSUT()

    await assert {
      try await sut.updateUser(
        id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
        AdminUpdateUser(banDuration: .zero)
      )
    }

    try transport.assertFirstRequestSnapshot(
      .put, "admin/users/E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
    ) {
      #"""
      curl \
      	--request PUT \
      	--header "Authorization: Bearer dummy.secret.key" \
      	--header "Content-Length: 23" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: dummy.secret.key" \
      	--data "{\"ban_duration\":\"none\"}" \
      	"http://localhost:54321/auth/v1/admin/users/E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
      """#
    }
  }

  @Test
  func adminSoftDeleteUser() async throws {
    let sut = makeAdminSUT()

    await assert {
      try await sut.deleteUser(
        id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!, softDelete: true)
    }

    try transport.assertFirstRequestSnapshot(
      .delete, "admin/users/E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
    ) {
      #"""
      curl \
      	--request DELETE \
      	--header "Authorization: Bearer dummy.secret.key" \
      	--header "Content-Length: 27" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: dummy.secret.key" \
      	--data "{\"should_soft_delete\":true}" \
      	"http://localhost:54321/auth/v1/admin/users/E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
      """#
    }
  }

  @Test
  func adminListUsers() async throws {
    let sut = makeAdminSUT()

    await assert {
      _ = try await sut.listUsers(page: 2, pageSize: 10)
    }

    try transport.assertFirstRequestSnapshot(.get, "admin/users") {
      #"""
      curl \
      	--header "Authorization: Bearer dummy.secret.key" \
      	--header "X-Client-Info: auth-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: dummy.secret.key" \
      	"http://localhost:54321/auth/v1/admin/users?page=2&per_page=10"
      """#
    }
  }

  @Test
  func adminGenerateLink() async throws {
    let sut = makeAdminSUT()

    await assert {
      _ = try await sut.generateLink(
        .magicLink(
          email: "example@mail.com", redirectTo: URL(string: "https://supabase.com"))
      )
    }

    try transport.assertFirstRequestSnapshot(.post, "admin/generate_link") {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer dummy.secret.key" \
      	--header "Content-Length: 47" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: dummy.secret.key" \
      	--data "{\"email\":\"example@mail.com\",\"type\":\"magiclink\"}" \
      	"http://localhost:54321/auth/v1/admin/generate_link?redirect_to=https://supabase.com"
      """#
    }
  }

  @Test
  func adminListCustomProviders() async throws {
    let sut = makeAdminSUT()

    await assert {
      _ = try await sut.customProviders.list(type: .oidc)
    }

    try transport.assertFirstRequestSnapshot(.get, "admin/custom-providers") {
      #"""
      curl \
      	--header "Authorization: Bearer dummy.secret.key" \
      	--header "X-Client-Info: auth-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: dummy.secret.key" \
      	"http://localhost:54321/auth/v1/admin/custom-providers?type=oidc"
      """#
    }
  }

  @Test
  func adminCreateCustomProvider() async throws {
    let sut = makeAdminSUT()

    var params = CreateCustomProvider.oauth2(
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

    try transport.assertFirstRequestSnapshot(.post, "admin/custom-providers") {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer dummy.secret.key" \
      	--header "Content-Length: 350" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: dummy.secret.key" \
      	--data "{\"authorization_url\":\"https:\/\/acme.example.com\/authorize\",\"client_id\":\"client-id\",\"client_secret\":\"client-secret\",\"custom_claims_allowlist\":[\"groups\"],\"identifier\":\"custom:acme\",\"name\":\"Acme\",\"provider_type\":\"oauth2\",\"scopes\":[\"openid\",\"email\"],\"token_url\":\"https:\/\/acme.example.com\/token\",\"userinfo_url\":\"https:\/\/acme.example.com\/userinfo\"}" \
      	"http://localhost:54321/auth/v1/admin/custom-providers"
      """#
    }
  }

  @Test
  func adminGetCustomProvider() async throws {
    let sut = makeAdminSUT()

    await assert {
      _ = try await sut.customProviders.provider(identifier: "custom:acme")
    }

    try transport.assertFirstRequestSnapshot(.get, "admin/custom-providers/custom:acme") {
      #"""
      curl \
      	--header "Authorization: Bearer dummy.secret.key" \
      	--header "X-Client-Info: auth-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: dummy.secret.key" \
      	"http://localhost:54321/auth/v1/admin/custom-providers/custom:acme"
      """#
    }
  }

  @Test
  func adminUpdateCustomProvider() async throws {
    let sut = makeAdminSUT()

    await assert {
      try await sut.customProviders.update(
        identifier: "custom:acme",
        UpdateCustomProvider(name: "Acme Inc.", customClaimsAllowlist: [])
      )
    }

    try transport.assertFirstRequestSnapshot(.put, "admin/custom-providers/custom:acme") {
      #"""
      curl \
      	--request PUT \
      	--header "Authorization: Bearer dummy.secret.key" \
      	--header "Content-Length: 49" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: dummy.secret.key" \
      	--data "{\"custom_claims_allowlist\":[],\"name\":\"Acme Inc.\"}" \
      	"http://localhost:54321/auth/v1/admin/custom-providers/custom:acme"
      """#
    }
  }

  private static let credential: JSONValue = [
    "id": "credential-id",
    "rawId": "cmF3LWNyZWRlbnRpYWwtaWQ",
    "type": "public-key",
    "response": [
      "clientDataJSON": "Y2xpZW50LWRhdGE",
      "attestationObject": "YXR0ZXN0YXRpb24tb2JqZWN0",
    ],
  ]

  private func assert(_ block: () async throws -> Void) async {
    do {
      try await block()
    } catch is UnimplementedError {
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  private func makeAdminSUT() -> AuthAdminClient {
    .testing(secretKey: "dummy.secret.key", http: transport)
  }

  private func makeSUT(redirectTo: URL? = nil) -> AuthClient {
    let configuration = AuthClient.Configuration(
      url: clientURL,
      storageKey: uniqueStorageKey(),
      headers: [HTTPField.Name("Apikey")!: "dummy.api.key", .xClientInfo: "gotrue-swift/x.y.z"],
      storage: InMemoryTestStorage(),
      redirectTo: redirectTo,
      autoRefresh: .manual,
      http: .init(transport: transport)
    )

    let pkce = PKCE(
      generateCodeVerifier: { "verifier" },
      generateCodeChallenge: { _ in "challenge" }
    )
    return AuthClient(configuration: configuration, pkce: pkce, platform: .live)
  }
}
