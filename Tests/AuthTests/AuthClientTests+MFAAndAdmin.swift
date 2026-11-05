import ConcurrencyExtras
import CustomDump
import Foundation
import Helpers
import InlineSnapshotTesting
import TestHelpers
import Testing

@_spi(Experimental) @testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

#if canImport(AuthenticationServices)
  import AuthenticationServices
#endif

extension AuthClientTests {
  @Test
  func mfaUnenroll() async throws {
    let factorID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

    transport.stub(
      .delete, "factors/\(factorID)",
      data: Data(#"{"id":"00000000-0000-0000-0000-000000000123"}"#.utf8)
    ) {
      #"""
      curl \
      	--request DELETE \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/factors/00000000-0000-0000-0000-000000000123"
      """#
    }

    let sut = makeSUT()

    try await sut.seedSession(.valid)

    let response = try await sut.mfa.unenroll(factorID: factorID)

    expectNoDifference(response, AuthMFAUnenrollResponse(id: factorID))
  }

  /// A 2xx body that does not decode is a client-side failure, never a server error (#904).
  @Test
  func mfaUnenrollUndecodableSuccessBodyThrowsDecoding() async throws {
    let factorID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

    transport.stub(.delete, "factors/\(factorID)", data: Data("{}".utf8))

    let sut = makeSUT()

    try await sut.seedSession(.valid)

    let error = await #expect(throws: AuthError.self) {
      try await sut.mfa.unenroll(factorID: factorID)
    }
    expectNoDifference(error?.kind, .decoding)
  }

  @Test
  func mfaChallengeAndVerify() async throws {
    let factorID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

    transport.stub(
      .post, "factors/\(factorID)/challenge",
      data: Data(
        """
        {
          "id": "e621e1f8-c36c-495a-93fc-0c247a3e6e5f",
          "type": "totp",
          "expires_at": 12345678
        }
        """.utf8
      )
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 2" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{}" \
      	"http://localhost:54321/auth/v1/factors/00000000-0000-0000-0000-000000000123/challenge"
      """#
    }

    transport.stub(.post, "factors/\(factorID)/verify", data: MockData.session) {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 119" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"challenge_id\":\"E621E1F8-C36C-495A-93FC-0C247A3E6E5F\",\"code\":\"456\",\"factor_id\":\"00000000-0000-0000-0000-000000000123\"}" \
      	"http://localhost:54321/auth/v1/factors/00000000-0000-0000-0000-000000000123/verify"
      """#
    }

    let sut = makeSUT()

    try await sut.seedSession(.valid)

    let session = try await sut.mfa.challengeAndVerify(factorID: factorID, code: "456")

    expectNoDifference(sut.currentSession, session)
  }

  @Test
  func mfaFactorsFetchesUserAndSplitsByStatus() async throws {
    let totpVerified = Factor(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      friendlyName: nil,
      factorType: .totp,
      status: .verified,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let phoneUnverified = Factor(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
      friendlyName: nil,
      factorType: .phone,
      status: .unverified,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let recoveryCodes = Factor(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
      friendlyName: "Recovery codes",
      factorType: .recoveryCode,
      status: .verified,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    var user = User(fromMockNamed: "user")
    user.factors = [totpVerified, phoneUnverified, recoveryCodes]

    transport.stub(.get, "user", data: try AuthClient.Configuration.jsonEncoder.encode(user))

    let sut = makeSUT()

    // The cached user has no factors, so the result can only come from `GET /user`.
    try await sut.seedSession(.valid)

    let factors = try await sut.mfa.factors()

    expectNoDifference(factors.verified, [totpVerified, recoveryCodes])
    expectNoDifference(factors.unverified, [phoneUnverified])
    expectNoDifference(factors.all, [totpVerified, recoveryCodes, phoneUnverified])
  }

  @Test
  func mfaFactorsWhenUserHasNoFactorsReturnsEmpty() async throws {
    transport.stub(.get, "user", data: MockData.user)

    let sut = makeSUT()

    try await sut.seedSession(.valid)

    let factors = try await sut.mfa.factors()

    expectNoDifference(factors, MFAFactors(verified: [], unverified: []))
  }

  @Test
  func passkeyRegistrationOptionsDecodeTheChallengeID() async throws {
    transport.stub(
      .post, "passkeys/registration/options",
      data: Data(
        """
        {
          "challenge_id": "e621e1f8-c36c-495a-93fc-0c247a3e6e5f",
          "expires_at": 1705312800,
          "options": {
            "challenge": "Y2hhbGxlbmdl",
            "rp": { "id": "example.com", "name": "Example" },
            "user": { "id": "dXNlci1pZA", "name": "user@example.com", "displayName": "User" },
            "pubKeyCredParams": [{ "alg": -7, "type": "public-key" }]
          }
        }
        """.utf8
      )
    )

    let sut = makeSUT()
    try await sut.seedSession(.valid)

    let options = try await sut.passkeys.registrationOptions()

    expectNoDifference(
      options.challengeID, UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!)
    expectNoDifference(options.options.objectValue?["challenge"]?.stringValue, "Y2hhbGxlbmdl")
    expectNoDifference(options.options.objectValue?["pubKeyCredParams"]?.arrayValue?.count, 1)
  }

  @Test
  func listPasskeysReturnsItems() async throws {
    transport.stub(
      .get, "passkeys/",
      data: Data(
        """
        [
          {
            "id": "11111111-1111-1111-1111-111111111111",
            "friendly_name": "Work Laptop",
            "created_at": "2024-01-15T10:00:00.000Z",
            "last_used_at": "2024-02-01T08:30:00.000Z"
          },
          {
            "id": "22222222-2222-2222-2222-222222222222",
            "friendly_name": null,
            "created_at": "2024-01-16T10:00:00.000Z",
            "last_used_at": null
          }
        ]
        """.utf8
      )
    )

    let sut = makeSUT()
    try await sut.seedSession(.valid)

    let passkeys = try await sut.passkeys.list()

    expectNoDifference(
      passkeys.map(\.id),
      [
        UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
      ]
    )
    expectNoDifference(passkeys[0].friendlyName, "Work Laptop")
    expectNoDifference(passkeys[1].friendlyName, nil)
    expectNoDifference(passkeys[1].lastUsedAt, nil)
  }

  @Test
  func verifyPasskeyAuthenticationUpdatesSession() async throws {
    transport.stub(.post, "passkeys/authentication/verify", data: MockData.session)

    let sut = makeSUT()

    let response = try await sut.passkeys.verifyAuthentication(
      challengeID: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
      credential: [
        "id": "credential-id",
        "rawId": "cmF3LWlk",
        "type": "public-key",
        "response": [
          "clientDataJSON": "Y2xpZW50LWRhdGE",
          "authenticatorData": "YXV0aA",
          "signature": "c2ln",
        ],
      ]
    )

    expectNoDifference(sut.currentSession, response)
  }

  #if canImport(AuthenticationServices) && !os(watchOS)
    @Test
    @MainActor
    func passkeySignInForwardsBareOptionsAndCommitsSession() async throws {
      transport.stub(
        .post, "passkeys/authentication/options",
        data: Data(
          #"{"challenge_id":"e621e1f8-c36c-495a-93fc-0c247a3e6e5f","expires_at":1705312800,"options":{"challenge":"Y2hhbGxlbmdl","rpId":"example.com","allowCredentials":[{"id":"Y3JlZA","type":"public-key"}]}}"#
            .utf8)
      )
      transport.stub(.post, "passkeys/authentication/verify", data: MockData.session)

      let forwardedOptions = LockIsolated<WebAuthnRequestOptions?>(nil)
      let authenticator = WebAuthnAuthenticator.fake(
        authenticate: { options, _ in
          forwardedOptions.setValue(options)
          return ["id": "cred"]
        }
      )

      let sut = makeSUT()

      let session = try await sut.passkeys.signIn(anchor: nil, authenticator: authenticator)

      expectNoDifference(sut.currentSession, session)
      expectNoDifference(
        forwardedOptions.value,
        WebAuthnRequestOptions(
          rpID: "example.com",
          challenge: Data("challenge".utf8),
          allowedCredentialIDs: [Data("cred".utf8)]
        )
      )
      expectNoDifference(
        try transport.lastJSONBody(.post, "passkeys/authentication/verify"),
        ["challenge_id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F", "credential": ["id": "cred"]]
      )
    }

    @Test
    @MainActor
    func passkeyRegisterForwardsBareOptions() async throws {
      transport.stub(
        .post, "passkeys/registration/options",
        data: Data(
          #"{"challenge_id":"e621e1f8-c36c-495a-93fc-0c247a3e6e5f","expires_at":1705312800,"options":{"challenge":"Y2hhbGxlbmdl","rp":{"id":"example.com"},"user":{"id":"dXNlci1pZA","name":"u@e.com"},"excludeCredentials":[{"id":"b2xk","type":"public-key"}]}}"#
            .utf8)
      )
      transport.stub(
        .post, "passkeys/registration/verify",
        data: Data(
          #"{"id":"11111111-1111-1111-1111-111111111111","friendly_name":"iCloud Keychain","created_at":"2024-01-15T10:00:00.000Z","last_used_at":null}"#
            .utf8)
      )

      let forwardedOptions = LockIsolated<WebAuthnCreationOptions?>(nil)
      let authenticator = WebAuthnAuthenticator.fake(
        register: { options, _ in
          forwardedOptions.setValue(options)
          return ["id": "cred"]
        }
      )

      let sut = makeSUT()
      try await sut.seedSession(.valid)

      let passkey = try await sut.passkeys.register(anchor: nil, authenticator: authenticator)

      expectNoDifference(passkey.id, UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
      expectNoDifference(
        forwardedOptions.value,
        WebAuthnCreationOptions(
          rpID: "example.com",
          challenge: Data("challenge".utf8),
          userID: Data("user-id".utf8),
          userName: "u@e.com",
          excludedCredentialIDs: [Data("old".utf8)]
        )
      )
    }

    @Test
    @MainActor
    func mfaEnrollWebAuthnUnwrapsPublicKeyAndSendsCreateType() async throws {
      transport.stub(
        .post, "factors",
        data: Data(#"{"id":"00000000-0000-0000-0000-000000000001","type":"webauthn"}"#.utf8)
      )
      transport.stub(
        .post, "factors/00000000-0000-0000-0000-000000000001/challenge",
        data: Data(
          #"{"id":"e621e1f8-c36c-495a-93fc-0c247a3e6e5f","type":"webauthn","expires_at":12345678,"webauthn":{"type":"create","credential_options":{"publicKey":{"challenge":"Y2hhbGxlbmdl","rp":{"id":"example.com"},"user":{"id":"dXNlci1pZA","name":"u@e.com"}}}}}"#
            .utf8)
      )
      transport.stub(
        .post, "factors/00000000-0000-0000-0000-000000000001/verify", data: MockData.session)

      let forwardedRpID = LockIsolated<String?>(nil)
      let authenticator = WebAuthnAuthenticator.fake(
        register: { options, _ in
          forwardedRpID.setValue(options.rpID)
          return ["id": "cred"]
        }
      )

      let sut = makeSUT()
      try await sut.seedSession(.valid)

      let session = try await sut.mfa.enrollWebAuthn(
        friendlyName: "My Passkey",
        anchor: nil,
        authenticator: authenticator
      )

      expectNoDifference(sut.currentSession, session)
      expectNoDifference(forwardedRpID.value, "example.com")
      expectNoDifference(
        try transport.lastJSONBody(
          .post, "factors/00000000-0000-0000-0000-000000000001/verify")?.objectValue?["webauthn"],
        ["type": "create", "credential_response": ["id": "cred"]]
      )
    }

    @Test
    @MainActor
    func mfaVerifyWebAuthnUnwrapsPublicKeyAndSendsRequestType() async throws {
      transport.stub(
        .post, "factors/00000000-0000-0000-0000-000000000001/challenge",
        data: Data(
          #"{"id":"e621e1f8-c36c-495a-93fc-0c247a3e6e5f","type":"webauthn","expires_at":12345678,"webauthn":{"type":"request","credential_options":{"publicKey":{"challenge":"Y2hhbGxlbmdl","rpId":"example.com"}}}}"#
            .utf8)
      )
      transport.stub(
        .post, "factors/00000000-0000-0000-0000-000000000001/verify", data: MockData.session)

      let forwardedRpID = LockIsolated<String?>(nil)
      let authenticator = WebAuthnAuthenticator.fake(
        authenticate: { options, _ in
          forwardedRpID.setValue(options.rpID)
          return ["id": "cred"]
        }
      )

      let sut = makeSUT()
      try await sut.seedSession(.valid)

      let session = try await sut.mfa.verifyWebAuthn(
        factorID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        anchor: nil,
        authenticator: authenticator
      )

      expectNoDifference(sut.currentSession, session)
      expectNoDifference(forwardedRpID.value, "example.com")
      expectNoDifference(
        try transport.lastJSONBody(
          .post, "factors/00000000-0000-0000-0000-000000000001/verify")?.objectValue?["webauthn"],
        ["type": "request", "credential_response": ["id": "cred"]]
      )
    }

    @Test
    @MainActor
    func mfaVerifyWebAuthnThrowsWhenTheFactorIsNotVerified() async throws {
      transport.stub(
        .post, "factors/00000000-0000-0000-0000-000000000001/challenge",
        data: Data(
          #"{"id":"e621e1f8-c36c-495a-93fc-0c247a3e6e5f","type":"webauthn","expires_at":12345678,"webauthn":{"type":"create","credential_options":{"publicKey":{"challenge":"Y2hhbGxlbmdl","rp":{"id":"example.com"},"user":{"id":"dXNlci1pZA","name":"u@e.com"}}}}}"#
            .utf8)
      )
      transport.stub(
        .post, "factors/00000000-0000-0000-0000-000000000001/verify", data: MockData.session)
      let sheetShown = LockIsolated(false)

      let sut = makeSUT()
      try await sut.seedSession(.valid)

      let error = await #expect(throws: AuthError.self) {
        try await sut.mfa.verifyWebAuthn(
          factorID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
          anchor: nil,
          authenticator: .fake(
            register: { _, _ in
              sheetShown.setValue(true)
              return [:]
            },
            authenticate: { _, _ in
              sheetShown.setValue(true)
              return [:]
            }
          )
        )
      }
      #expect(error?.kind == .mfaFactorNotVerified)
      #expect(!sheetShown.value)
      #expect(
        transport.requests(.post, "factors/00000000-0000-0000-0000-000000000001/verify").isEmpty)
    }

    @Test
    @MainActor
    func mfaVerifyWebAuthnThrowsDecodingWhenPublicKeyIsMissing() async throws {
      transport.stub(
        .post, "factors/00000000-0000-0000-0000-000000000001/challenge",
        data: Data(
          #"{"id":"e621e1f8-c36c-495a-93fc-0c247a3e6e5f","type":"webauthn","expires_at":12345678,"webauthn":{"type":"request","credential_options":{"challenge":"Y2hhbGxlbmdl","rpId":"example.com"}}}"#
            .utf8)
      )

      let sut = makeSUT()
      try await sut.seedSession(.valid)

      await #expect {
        try await sut.mfa.verifyWebAuthn(
          factorID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
          anchor: nil,
          authenticator: .fake()
        )
      } throws: { error in
        (error as? AuthError)?.kind == .decoding
      }
    }
  #endif

  @Test
  func mfaAssuranceLevelReadsFactorsFromAFreshUser() async throws {
    var session = Session.valid

    session.accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJhYWwiOiJhYWwxIiwiYW1yIjpbeyJtZXRob2QiOiJ0b3RwIiwidGltZXN0YW1wIjoxNTE2MjM5MDIyfSx7Im1ldGhvZCI6InBob25lIiwidGltZXN0YW1wIjoxNTE2MjM5MDIyfV19.OQy2SmA1hcw9V5wrY-bvORjbFh5tWznLIfcMCqPu_6M"

    var user = User(fromMockNamed: "user")
    user.factors = [
      Factor(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        friendlyName: nil,
        factorType: .totp,
        status: .verified,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
      )
    ]

    transport.stub(.get, "user", data: try AuthClient.Configuration.jsonEncoder.encode(user))

    let sut = makeSUT()

    // The cached user has no factors, so `nextLevel` can only come from `GET /user`.
    try await sut.seedSession(session)

    let info = try await sut.mfa.assuranceLevel()

    expectNoDifference(
      info,
      AssuranceLevelInfo(
        currentLevel: .aal1,
        nextLevel: .aal2,
        currentAuthenticationMethods: [
          AMREntry(method: .totp, timestamp: Date(timeIntervalSince1970: 1_516_239_022)),
          AMREntry(method: "phone", timestamp: Date(timeIntervalSince1970: 1_516_239_022)),
        ]
      )
    )
    expectNoDifference(sut.currentSession, session)
  }

  @Test
  func mfaAssuranceLevelWithUndecodableTokenThrowsDecoding() async throws {
    let sut = makeSUT()

    // `Session.valid.accessToken` is not a JWT.
    try await sut.seedSession(.valid)

    let error = await #expect(throws: AuthError.self) {
      try await sut.mfa.assuranceLevel()
    }
    expectNoDifference(error?.kind, .decoding)
  }

  @Test
  func mfaAssuranceLevelWithoutSessionThrowsSessionMissing() async throws {
    let sut = makeSUT()

    let error = await #expect(throws: AuthError.self) {
      try await sut.mfa.assuranceLevel()
    }
    expectNoDifference(error?.kind, .sessionMissing)
  }

  @Test
  func getUserById() async throws {
    let id = UUID(uuidString: "859f402d-b3de-4105-a1b9-932836d9193b")!
    let sut = AuthAdminClient.testing(secretKey: apiKey, http: transport)

    transport.stub(.get, "admin/users/\(id)", data: MockData.user) {
      #"""
      curl \
      	--header "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/admin/users/859F402D-B3DE-4105-A1B9-932836D9193B"
      """#
    }

    let user = try await sut.user(id: id)

    expectNoDifference(user.id, id)
  }

  @Test
  func adminUpdateUser() async throws {
    let id = UUID(uuidString: "859f402d-b3de-4105-a1b9-932836d9193b")!
    let sut = AuthAdminClient.testing(secretKey: apiKey, http: transport)

    transport.stub(.put, "admin/users/\(id)", data: MockData.user) {
      #"""
      curl \
      	--request PUT \
      	--header "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--header "Content-Length: 63" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"phone\":\"1234567890\",\"user_metadata\":{\"full_name\":\"John Doe\"}}" \
      	"http://localhost:54321/auth/v1/admin/users/859F402D-B3DE-4105-A1B9-932836D9193B"
      """#
    }

    let attributes = AdminUserAttributes(
      phone: "1234567890",
      userMetadata: [
        "full_name": "John Doe"
      ]
    )

    let user = try await sut.updateUser(id: id, attributes: attributes)

    expectNoDifference(user.id, id)
  }

  @Test
  func createUser() async throws {
    let sut = AuthAdminClient.testing(secretKey: apiKey, http: transport)

    transport.stub(.post, "admin/users", data: MockData.user) {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--header "Content-Length: 98" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"email\":\"test@example.com\",\"password\":\"password\",\"password_hash\":\"password\",\"phone\":\"1234567890\"}" \
      	"http://localhost:54321/auth/v1/admin/users"
      """#
    }

    let attributes = AdminUserAttributes(
      email: "test@example.com",
      password: "password",
      passwordHash: "password",
      phone: "1234567890"
    )

    _ = try await sut.createUser(attributes)
  }

  @Test
  func createUserConfirmingEmailAndPhone() async throws {
    let sut = AuthAdminClient.testing(secretKey: apiKey, http: transport)

    transport.stub(.post, "admin/users", data: MockData.user) {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--header "Content-Length: 113" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"email\":\"test@example.com\",\"email_confirm\":true,\"password\":\"password\",\"phone\":\"1234567890\",\"phone_confirm\":true}" \
      	"http://localhost:54321/auth/v1/admin/users"
      """#
    }

    let attributes = AdminUserAttributes(
      email: "test@example.com",
      confirmsEmail: true,
      password: "password",
      phone: "1234567890",
      confirmsPhone: true
    )

    _ = try await sut.createUser(attributes)
  }

  @Test
  func adminUpdateUserConfirmingEmail() async throws {
    let id = UUID(uuidString: "859f402d-b3de-4105-a1b9-932836d9193b")!
    let sut = AuthAdminClient.testing(secretKey: apiKey, http: transport)

    transport.stub(.put, "admin/users/\(id)", data: MockData.user) {
      #"""
      curl \
      	--request PUT \
      	--header "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--header "Content-Length: 22" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"email_confirm\":true}" \
      	"http://localhost:54321/auth/v1/admin/users/859F402D-B3DE-4105-A1B9-932836D9193B"
      """#
    }

    let user = try await sut.updateUser(
      id: id,
      attributes: AdminUserAttributes(confirmsEmail: true)
    )

    expectNoDifference(user.id, id)
  }

  @Test
  func adminInviteUser() async throws {
    let sut = AuthAdminClient.testing(secretKey: apiKey, http: transport)

    transport.stub(.post, "invite", data: MockData.user) {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--header "Content-Length: 60" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"data\":{\"full_name\":\"John Doe\"},\"email\":\"test@example.com\"}" \
      	"http://localhost:54321/auth/v1/invite?redirect_to=https://example.com"
      """#
    }

    _ = try await sut.inviteUser(
      email: "test@example.com",
      userMetadata: ["full_name": "John Doe"],
      redirectTo: URL(string: "https://example.com")
    )
  }

  @Test
  func removeSessionAndSignoutIfSessionNotFoundErrorReturned() async throws {
    let sut = makeSUT()

    transport.stub(
      .get, "user", status: .forbidden,
      data: Data(
        """
        {
          "error_code": "session_not_found",
          "message": "Session not found"
        }
        """.utf8
      )
    )

    try await sut.seedSession(.valid)

    try await assertAuthStateChanges(
      sut: sut,
      action: {
        do {
          _ = try await sut.user()
          Issue.record("Expected failure")
        } catch {
          #expect((error as? AuthError)?.kind == .sessionInvalidated)
        }
      },
      expectedEvents: [.initialSession, .signedOut]
    )

    #expect(sut.dependencies.sessionStore.currentStatus == .signedOut(.sessionRevoked))
  }

  @Test
  func signInRejectedAsBannedKeepsStoredSession() async throws {
    let sut = makeSUT()

    transport.stub(
      .post, "token", status: .forbidden,
      data: Data(
        """
        {
          "error_code": "user_banned",
          "msg": "User is banned"
        }
        """.utf8
      )
    )

    try await sut.seedSession(.valid)

    try await assertAuthStateChanges(
      sut: sut,
      action: {
        do {
          try await sut.signIn(email: "banned@example.com", password: "secret")
          Issue.record("Expected failure")
        } catch {
          #expect((error as? AuthError)?.errorCode == .userBanned)
        }
      },
      expectedEvents: [.initialSession]
    )

    #expect(sut.currentSession == .valid)
  }

  @Test
  func userWithForeignJWTKeepsStoredSessionIfSessionNotFoundErrorReturned() async throws {
    let sut = makeSUT()

    transport.stub(
      .get, "user", status: .forbidden,
      data: Data(
        """
        {
          "error_code": "session_not_found",
          "message": "Session not found"
        }
        """.utf8
      )
    )

    try await sut.seedSession(.valid)

    try await assertAuthStateChanges(
      sut: sut,
      action: {
        do {
          _ = try await sut.user(jwt: "foreign-access-token")
          Issue.record("Expected failure")
        } catch {
          #expect((error as? AuthError)?.kind == .sessionInvalidated)
        }
      },
      expectedEvents: [.initialSession]
    )

    #expect(sut.currentSession == .valid)
  }

  @Test
  func userWithForeignJWTWhileSignedOutKeepsTheSignOutReason() async throws {
    let sut = makeSUT()

    transport.stub(
      .get, "user", status: .forbidden,
      data: Data(
        """
        {
          "error_code": "session_not_found",
          "message": "Session not found"
        }
        """.utf8
      )
    )

    await sut.initialization()

    try await assertAuthStateChanges(
      sut: sut,
      action: {
        do {
          _ = try await sut.user(jwt: "foreign-access-token")
          Issue.record("Expected failure")
        } catch {
          #expect((error as? AuthError)?.kind == .sessionInvalidated)
        }
      },
      expectedEvents: [.initialSession]
    )

    #expect(sut.dependencies.sessionStore.currentStatus == .signedOut(.sessionMissing))
  }

  @Test
  func userWithStoredJWTRemovesSessionIfSessionNotFoundErrorReturned() async throws {
    let sut = makeSUT()

    transport.stub(
      .get, "user", status: .forbidden,
      data: Data(
        """
        {
          "error_code": "session_not_found",
          "message": "Session not found"
        }
        """.utf8
      )
    )

    try await sut.seedSession(.valid)

    try await assertAuthStateChanges(
      sut: sut,
      action: {
        do {
          _ = try await sut.user(jwt: Session.valid.accessToken)
          Issue.record("Expected failure")
        } catch {
          #expect((error as? AuthError)?.kind == .sessionInvalidated)
        }
      },
      expectedEvents: [.initialSession, .signedOut]
    )

    #expect(sut.currentSession == nil)
  }

  @Test
  func importSessionWithForeignTokenKeepsStoredSessionIfSessionNotFoundErrorReturned()
    async throws
  {
    let sut = makeSUT()

    transport.stub(
      .get, "user", status: .forbidden,
      data: Data(
        """
        {
          "error_code": "session_not_found",
          "message": "Session not found"
        }
        """.utf8
      )
    )

    try await sut.seedSession(.valid)

    let accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjo0ODUyMTYzNTkzLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.UiEhoahP9GNrBKw_OHBWyqYudtoIlZGkrjs7Qa8hU7I"

    try await assertAuthStateChanges(
      sut: sut,
      action: {
        do {
          _ = try await sut.importSession(
            accessToken: accessToken, refreshToken: "dummy-refresh-token")
          Issue.record("Expected failure")
        } catch {
          #expect((error as? AuthError)?.kind == .sessionInvalidated)
        }
      },
      expectedEvents: [.initialSession]
    )

    #expect(sut.currentSession == .valid)
  }

  @Test
  func sessionWithURL_implicitFlow_keepsStoredSessionIfSessionNotFoundErrorReturned() async throws {
    let sut = makeSUT()

    transport.stub(
      .get, "user", status: .forbidden,
      data: Data(
        """
        {
          "error_code": "session_not_found",
          "message": "Session not found"
        }
        """.utf8
      )
    )

    try await sut.seedSession(.valid)

    let url = URL(
      string:
        "https://dummy-url.com/callback#access_token=foreign-access-token&expires_in=60&refresh_token=refreshtoken&token_type=bearer"
    )!

    try await assertAuthStateChanges(
      sut: sut,
      action: {
        do {
          _ = try await sut.handleRedirect(url)
          Issue.record("Expected failure")
        } catch {
          #expect((error as? AuthError)?.kind == .sessionInvalidated)
        }
      },
      expectedEvents: [.initialSession]
    )

    #expect(sut.currentSession == .valid)
  }

}
