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
  func updateUser() async throws {
    transport.stub(.put, "user", data: MockData.user) {
      #"""
      curl \
      	--request PUT \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 228" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"code_challenge\":\"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY\",\"code_challenge_method\":\"s256\",\"data\":{\"custom_key\":\"custom_value\"},\"email\":\"example@mail.com\",\"nonce\":\"abcdef\",\"password\":\"another.pass\",\"phone\":\"+1 202-918-2132\"}" \
      	"http://localhost:54321/auth/v1/user"
      """#
    }

    let sut = makeSUT()

    try await sut.seedSession(.valid)

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

  @Test
  func resetPassword() async throws {
    transport.stub(.post, "recover") {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 179" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"code_challenge\":\"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY\",\"code_challenge_method\":\"s256\",\"email\":\"example@mail.com\",\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"}}" \
      	"http://localhost:54321/auth/v1/recover?redirect_to=https://supabase.com"
      """#
    }

    let sut = makeSUT()
    try await sut.resetPassword(
      email: "example@mail.com",
      options: .init(
        redirectTo: URL(string: "https://supabase.com"), captchaToken: "captcha-token")
    )
  }

  @Test
  func pkceExchangeAfterResetPasswordEmitsPasswordRecovery() async throws {
    transport.stub(.post, "recover")
    transport.stub(.post, "token", data: MockData.session)
    let sut = makeSUT()

    try await sut.resetPassword(email: "example@mail.com")

    try await assertAuthStateChanges(
      sut: sut,
      action: { try await sut.handleRedirect(URL(string: "https://supabase.com?code=12345")!) },
      expectedEvents: [.initialSession, .passwordRecovery]
    )
  }

  @Test
  func pkceExchangeOfASignInFlowEmitsSignedIn() async throws {
    transport.stub(.post, "token", data: MockData.session)
    let sut = makeSUT()
    _ = try await sut.dependencies.flowStore.start(purpose: .recovery, redirectTo: nil)
    let signIn = try await sut.dependencies.flowStore.start(purpose: .signIn, redirectTo: nil)

    try await assertAuthStateChanges(
      sut: sut,
      action: { try await sut.exchangeCodeForSession("12345", flowID: signIn.flow.id) },
      expectedEvents: [.initialSession, .signedIn]
    )
  }

  @Test
  func pkceExchangeOfAnEmailChangeForTheSignedInUserEmitsUserUpdated() async throws {
    transport.stub(.post, "token", data: MockData.session)
    let sut = makeSUT()
    let held = try AuthClient.Configuration.jsonDecoder.decode(
      Session.self, from: MockData.session
    ).received(at: Self.now)
    try await sut.seedSession(held)
    let flow = try await sut.dependencies.flowStore.start(purpose: .emailChange, redirectTo: nil)

    try await assertAuthStateChanges(
      sut: sut,
      action: { try await sut.exchangeCodeForSession("12345", flowID: flow.flow.id) },
      expectedEvents: [.initialSession, .userUpdated]
    )
  }

  @Test
  func emailChangeRequestsStoreAnEmailChangeFlow() async throws {
    transport.stub(.put, "user", data: MockData.user)
    transport.stub(.post, "resend")
    let sut = makeSUT()
    try await sut.seedSession(.valid)
    let flows = sut.dependencies.flowStore

    try await sut.updateUser(UserAttributes(email: "new@example.com"))
    #expect(try await flows.pendingFlows().first?.purpose == .emailChange)

    try await sut.resend(email: "example@mail.com", type: .signup)
    #expect(try await flows.pendingFlows().first?.purpose == .signIn)

    try await sut.resend(email: "example@mail.com", type: .emailChange)
    #expect(try await flows.pendingFlows().first?.purpose == .emailChange)
  }

  @Test
  func resendEmail() async throws {
    transport.stub(.post, "resend") {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 201" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"code_challenge\":\"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY\",\"code_challenge_method\":\"s256\",\"email\":\"example@mail.com\",\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"},\"type\":\"email_change\"}" \
      	"http://localhost:54321/auth/v1/resend?redirect_to=https://supabase.com"
      """#
    }

    let sut = makeSUT()

    try await sut.resend(
      email: "example@mail.com",
      type: .emailChange,
      options: .init(
        redirectTo: URL(string: "https://supabase.com"), captchaToken: "captcha-token")
    )
  }

  @Test
  func resendEmailImplicitFlow() async throws {
    transport.stub(.post, "resend") {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 201" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"code_challenge\":\"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY\",\"code_challenge_method\":\"s256\",\"email\":\"example@mail.com\",\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"},\"type\":\"email_change\"}" \
      	"http://localhost:54321/auth/v1/resend?redirect_to=https://supabase.com"
      """#
    }

    let sut = makeSUT()

    try await sut.resend(
      email: "example@mail.com",
      type: .emailChange,
      options: .init(
        redirectTo: URL(string: "https://supabase.com"), captchaToken: "captcha-token")
    )
  }

  @Test
  func resendPhone() async throws {
    transport.stub(.post, "resend", data: Data(#"{"message_id": "12345"}"#.utf8)) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 106" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"},\"phone\":\"+1 202-918-2132\",\"type\":\"phone_change\"}" \
      	"http://localhost:54321/auth/v1/resend"
      """#
    }

    let sut = makeSUT()

    let messageID = try await sut.resend(
      phone: "+1 202-918-2132",
      type: .phoneChange,
      options: .init(captchaToken: "captcha-token")
    )

    #expect(messageID == MessageID(rawValue: "12345"))
  }

  @Test
  func deleteUser() async throws {
    let id = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!

    transport.stub(.delete, "admin/users/\(id)", status: .noContent) {
      #"""
      curl \
      	--request DELETE \
      	--header "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--header "Content-Length: 28" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"should_soft_delete\":false}" \
      	"http://localhost:54321/auth/v1/admin/users/E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
      """#
    }

    let sut = AuthAdminClient.testing(secretKey: apiKey, http: transport)
    try await sut.deleteUser(id: id)
  }

  @Test
  func adminListPasskeysReturnsItems() async throws {
    let userId = UUID(uuidString: "859f402d-b3de-4105-a1b9-932836d9193b")!

    transport.stub(
      .get, "admin/users/\(userId)/passkeys",
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
      ))

    let sut = AuthAdminClient.testing(secretKey: apiKey, http: transport)

    let passkeys = try await sut.passkeys.list(forUser: userId)

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
  func adminDeletePasskey() async throws {
    let userId = UUID(uuidString: "859f402d-b3de-4105-a1b9-932836d9193b")!
    let passkeyId = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!

    transport.stub(.delete, "admin/users/\(userId)/passkeys/\(passkeyId)", status: .noContent) {
      #"""
      curl \
      	--request DELETE \
      	--header "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/admin/users/\#(userId)/passkeys/\#(passkeyId)"
      """#
    }

    let sut = AuthAdminClient.testing(secretKey: apiKey, http: transport)
    try await sut.passkeys.delete(id: passkeyId, forUser: userId)
  }

  @Test
  func reauthenticate() async throws {
    transport.stub(.get, "reauthenticate") {
      #"""
      curl \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/reauthenticate"
      """#
    }

    let sut = makeSUT()

    try await sut.seedSession(.valid)

    try await sut.reauthenticate()
  }

  @Test
  func unlinkIdentity() async throws {
    let identityId = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
    transport.stub(.delete, "user/identities/\(identityId.uuidString)", status: .noContent) {
      #"""
      curl \
      	--request DELETE \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/user/identities/E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
      """#
    }

    let sut = makeSUT()

    try await sut.seedSession(.valid)

    try await sut.unlinkIdentity(
      UserIdentity(
        id: identityId,
        providerUserID: "5923044",
        userID: UUID(),
        provider: .email,
        createdAt: Date(),
        lastSignInAt: Date(),
        updatedAt: Date()
      )
    )
  }

  @Test
  func unlinkIdentityEmitsUserUpdatedWithoutTheIdentity() async throws {
    let identities = try #require(Session.valid.user.identities)
    let unlinked = identities[0]
    transport.stub(.delete, "user/identities/\(unlinked.id.uuidString)", data: Data("{}".utf8))
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    try await assertAuthStateChanges(
      sut: sut,
      action: { try await sut.unlinkIdentity(unlinked) },
      expectedEvents: [.initialSession, .userUpdated]
    )

    expectNoDifference(sut.currentUser?.identities, Array(identities.dropFirst()))
  }

  @Test
  func unlinkIdentityOfAnotherUserEmitsNothing() async throws {
    var identity = try #require(Session.valid.user.identities?.first)
    identity.userID = UUID()
    transport.stub(.delete, "user/identities/\(identity.id.uuidString)", data: Data("{}".utf8))
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    try await assertAuthStateChanges(
      sut: sut,
      action: { try await sut.unlinkIdentity(identity) },
      expectedEvents: [.initialSession]
    )

    expectNoDifference(sut.currentUser, Session.valid.user)
  }

  @Test
  func identitiesReturnsEmptyWhenNull() async throws {
    transport.stub(
      .get, "user",
      data: Data(
        """
        {
          "id": "859f402d-b3de-4105-a1b9-932836d9193b",
          "aud": "authenticated",
          "identities": null,
          "created_at": "2022-04-09T11:23:45.874827Z",
          "updated_at": "2022-04-09T11:57:01.720803Z"
        }
        """.utf8
      ))
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    let identities = try await sut.identities()

    #expect(identities.isEmpty)
  }

  @Test
  func updateUserMergesIntoCurrentSession() async throws {
    let race = Race()
    let gate = Gate()
    race.answerSignIn { _ in race.issue("signed-in") }
    race.answerRefresh { try Race.ok(race.issue("refreshed")) }
    race.answerUserUpdate(through: gate, with: Race.user(nickname: "updated"))
    let client = race.makeClient()
    var events = client.events().makeAsyncIterator()
    #expect(await events.next()?.event == .initialSession)
    try await client.signIn(email: "a@example.com", password: "secret")
    #expect(await events.next()?.event == .signedIn)

    let update = Task {
      try await client.updateUser(UserAttributes(userMetadata: ["nickname": "updated"]))
    }
    await gate.arrivals(1)
    try await client.refreshSession()
    #expect(await events.next()?.event == .tokenRefreshed)
    gate.open()
    let returnedUser = try await update.value

    #expect(await events.next()?.event == .userUpdated)
    #expect(returnedUser.userMetadata["nickname"] == "updated")
    #expect(client.currentSession?.accessToken == "refreshed-access")
    expectNoDifference(client.currentSession?.user, returnedUser)
  }

  @Test
  func ssoSignInURLUsingDomain() async throws {
    transport.stub(.post, "sso", data: Data(#"{"url":"https://supabase.com"}"#.utf8)) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 241" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"code_challenge\":\"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY\",\"code_challenge_method\":\"s256\",\"domain\":\"supabase.com\",\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"},\"redirect_to\":\"https:\/\/supabase.com\",\"skip_http_redirect\":true}" \
      	"http://localhost:54321/auth/v1/sso"
      """#
    }

    let sut = makeSUT()

    let flow = try await sut.ssoSignInURL(
      .domain("supabase.com"),
      options: SSOOptions(
        redirectTo: URL(string: "https://supabase.com"),
        captchaToken: "captcha-token"
      )
    )

    expectNoDifference(flow.url, URL(string: "https://supabase.com")!)
  }

  @Test
  func ssoSignInURLUsingProviderID() async throws {
    transport.stub(.post, "sso", data: Data(#"{"url":"https://supabase.com"}"#.utf8)) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 270" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"code_challenge\":\"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY\",\"code_challenge_method\":\"s256\",\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"},\"provider_id\":\"E621E1F8-C36C-495A-93FC-0C247A3E6E5F\",\"redirect_to\":\"https:\/\/supabase.com\",\"skip_http_redirect\":true}" \
      	"http://localhost:54321/auth/v1/sso"
      """#
    }

    let sut = makeSUT()

    let flow = try await sut.ssoSignInURL(
      .providerID(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!),
      options: SSOOptions(
        redirectTo: URL(string: "https://supabase.com"),
        captchaToken: "captcha-token"
      )
    )

    expectNoDifference(flow.url, URL(string: "https://supabase.com")!)
  }

  @Test
  func mfaEnrollTOTP() async throws {
    transport.stub(
      .post, "factors",
      data: Data(
        """
        {
          "id": "00000000-0000-0000-0000-000000012345",
          "type": "totp",
          "friendly_name": "test",
          "totp": {
            "qr_code": "<svg />",
            "secret": "SECRET",
            "uri": "otpauth://totp/supabase.com:user?secret=SECRET"
          }
        }
        """.utf8
      )
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 69" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"factor_type\":\"totp\",\"friendly_name\":\"test\",\"issuer\":\"supabase.com\"}" \
      	"http://localhost:54321/auth/v1/factors"
      """#
    }

    let sut = makeSUT()

    try await sut.seedSession(.valid)

    let enrollment = try await sut.mfa.enrollTOTP(issuer: "supabase.com", friendlyName: "test")

    expectNoDifference(
      enrollment,
      TOTPEnrollment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000012345")!,
        friendlyName: "test",
        qrCode: "<svg />",
        secret: "SECRET",
        uri: "otpauth://totp/supabase.com:user?secret=SECRET"
      )
    )
  }

  @Test
  func mfaEnrollTOTPWithoutTOTPDataThrowsDecoding() async throws {
    transport.stub(
      .post, "factors",
      data: Data(#"{"id":"00000000-0000-0000-0000-000000012345","type":"totp"}"#.utf8))

    let sut = makeSUT()

    try await sut.seedSession(.valid)

    let error = await #expect(throws: AuthError.self) {
      try await sut.mfa.enrollTOTP()
    }
    expectNoDifference(error?.kind, .decoding)
  }

  @Test
  func mfaEnrollPhone() async throws {
    transport.stub(
      .post, "factors",
      data: Data(
        """
        {
          "id": "00000000-0000-0000-0000-000000012345",
          "type": "phone",
          "friendly_name": "test",
          "phone": "12029182132"
        }
        """.utf8
      )
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 72" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"factor_type\":\"phone\",\"friendly_name\":\"test\",\"phone\":\"+1 202-918-2132\"}" \
      	"http://localhost:54321/auth/v1/factors"
      """#
    }

    let sut = makeSUT()

    try await sut.seedSession(.valid)

    let enrollment = try await sut.mfa.enrollPhone("+1 202-918-2132", friendlyName: "test")

    expectNoDifference(
      enrollment,
      PhoneEnrollment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000012345")!,
        friendlyName: "test",
        phone: "12029182132"
      )
    )
  }

  @Test
  func mfaChallenge() async throws {
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

    let sut = makeSUT()

    try await sut.seedSession(.valid)

    let challenge = try await sut.mfa.challenge(factorID: factorID)

    expectNoDifference(
      challenge,
      MFAChallenge(
        id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
        factorType: .totp,
        expiresAt: Date(timeIntervalSince1970: 12_345_678)
      )
    )
  }

  @Test
  func mfaChallengeWithPhoneType() async throws {
    let factorID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

    transport.stub(
      .post, "factors/\(factorID)/challenge",
      data: Data(
        """
        {
          "id": "e621e1f8-c36c-495a-93fc-0c247a3e6e5f",
          "type": "phone",
          "expires_at": 12345678
        }
        """.utf8
      )
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 17" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"channel\":\"sms\"}" \
      	"http://localhost:54321/auth/v1/factors/00000000-0000-0000-0000-000000000123/challenge"
      """#
    }

    let sut = makeSUT()

    try await sut.seedSession(.valid)

    let challenge = try await sut.mfa.challenge(factorID: factorID, channel: .sms)

    expectNoDifference(
      challenge,
      MFAChallenge(
        id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
        factorType: .phone,
        expiresAt: Date(timeIntervalSince1970: 12_345_678)
      )
    )
  }

  @Test
  func mfaChallengeWebAuthnReturnsCredentialOptions() async throws {
    let factorID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

    transport.stub(
      .post, "factors/\(factorID)/challenge",
      data: Data(
        """
        {
          "id": "e621e1f8-c36c-495a-93fc-0c247a3e6e5f",
          "type": "webauthn",
          "expires_at": 12345678,
          "webauthn": {
            "type": "create",
            "credential_options": {
              "challenge": "Y2hhbGxlbmdl",
              "rp": { "id": "example.com", "name": "Example" },
              "pubKeyCredParams": [{ "alg": -7, "type": "public-key" }]
            }
          }
        }
        """.utf8
      ))

    let sut = makeSUT()

    try await sut.seedSession(.valid)

    let challenge = try await sut.mfa.challenge(
      factorID: factorID, webAuthn: .init(rpId: "example.com"))

    expectNoDifference(challenge.id, UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!)
    expectNoDifference(challenge.factorType, .webAuthn)
    expectNoDifference(challenge.webauthn?.type, .create)

    let options = challenge.webauthn?.credentialOptions.objectValue
    expectNoDifference(options?["challenge"]?.stringValue, "Y2hhbGxlbmdl")
    expectNoDifference(options?["pubKeyCredParams"]?.arrayValue?.count, 1)
  }

  @Test
  func mfaVerifyReplacesSessionAndEmitsEvent() async throws {
    let factorID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

    transport.stub(.post, "factors/\(factorID)/verify", data: MockData.session) {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 122" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"challenge_id\":\"E621E1F8-C36C-495A-93FC-0C247A3E6E5F\",\"code\":\"123456\",\"factor_id\":\"00000000-0000-0000-0000-000000000123\"}" \
      	"http://localhost:54321/auth/v1/factors/00000000-0000-0000-0000-000000000123/verify"
      """#
    }

    let sut = makeSUT()

    try await sut.seedSession(.valid)

    let changes = LockIsolated<[AuthChange]>([])
    let stream = sut.events()
    let collect = Task {
      for await change in stream {
        changes.withValue { $0.append(change) }
        if change.event == .mfaChallengeVerified { break }
      }
    }

    let session = try await sut.mfa.verify(
      factorID: factorID,
      challengeID: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
      code: "123456"
    )
    await collect.value

    expectNoDifference(sut.currentSession, session)
    #expect(session.refreshToken != Session.valid.refreshToken)
    expectNoDifference(changes.value.map(\.event), [.initialSession, .mfaChallengeVerified])
  }

}
