import ConcurrencyExtras
import Foundation
import Mocker
import TestHelpers
import Testing

@testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension AuthMockerTests {
  @Suite(.mockerSerialized, .mainSerialExecutorSerialized)
  struct AuthClientV3MethodsTests {
    init() {
      Mocker.removeAll()
    }

    @available(*, deprecated, message: "Compares with the deprecated v2 method.")
    @Test
    func signInWithIDTokenSendsTheV2Body() async throws {
      mock("token", data: MockData.session)
      let client = V3TestClient()

      let session = try await client.sut.signInWithIDToken(
        IDTokenCredentials(
          provider: .apple, idToken: "id-token", nonce: "nonce", accessToken: "access-token",
          captchaToken: "captcha"))
      #expect(session.accessToken == Session(fromMockNamed: "session").accessToken)
      #expect(client.query()["grant_type"] == "id_token")

      try await client.sut.signInWithIdToken(
        credentials: OpenIDConnectCredentials(
          provider: .apple, idToken: "id-token", accessToken: "access-token", nonce: "nonce",
          gotrueMetaSecurity: AuthMetaSecurity(captchaToken: "captcha")))

      #expect(client.body(at: 0) == client.body(at: 1))
      #expect(client.body(at: 0)?["provider"] as? String == "apple")
      #expect(client.body(at: 0)?["link_identity"] as? Bool == false)
    }

    @available(*, deprecated, message: "Compares with the deprecated v2 method.")
    @Test
    func signInWithWeb3SendsTheV2Body() async throws {
      mock("token", data: MockData.session)
      let client = V3TestClient()

      var credentials = Web3Credentials(chain: .ethereum, message: "message", signature: "0x1")
      credentials.captchaToken = "captcha"
      #expect(credentials.gotrueMetaSecurity == AuthMetaSecurity(captchaToken: "captcha"))
      #expect(credentials.captchaToken == "captcha")

      try await client.sut.signInWithWeb3(credentials)
      try await client.sut.signInWithWeb3(credentials: credentials)

      #expect(client.query()["grant_type"] == "web3")
      #expect(client.body(at: 0) == client.body(at: 1))
      #expect(client.body(at: 0)?["chain"] as? String == "ethereum")
    }

    @Test
    func importSessionRefreshesAnExpiredToken() async throws {
      mock("token", data: MockData.session)
      let client = V3TestClient()

      let session = try await client.sut.importSession(
        accessToken: "not-a-jwt", refreshToken: "refresh-token")

      #expect(session.accessToken == Session(fromMockNamed: "session").accessToken)
      #expect(client.query()["grant_type"] == "refresh_token")
      #expect(client.lastBody?["refresh_token"] as? String == "refresh-token")
      #expect(client.sut.currentSession == session)
    }

    @Test
    func identities() async throws {
      mock("user", .get, data: MockData.user)
      let client = V3TestClient()
      client.storeSession()

      let identities = try await client.sut.identities()

      #expect(identities == User(fromMockNamed: "user").identities ?? [])
    }

    @available(*, deprecated, message: "Compares with the deprecated v2 method.")
    @Test
    func updateUserSendsTheV2Body() async throws {
      mock("user", .put, data: MockData.user)
      let client = V3TestClient()
      client.storeSession()

      let user = try await client.sut.updateUser(
        UpdateUser(
          email: "example@mail.com", phone: "+1 202-918-2132", password: "another.pass",
          nonce: "abcdef", userMetadata: ["custom_key": "custom_value", "camelKey": 1]),
        redirectTo: URL(string: "myapp://callback"))
      #expect(user.id == User(fromMockNamed: "user").id)
      #expect(client.query()["redirect_to"] == "myapp://callback")

      try await client.sut.update(
        user: UserAttributes(
          email: "example@mail.com", phone: "+1 202-918-2132", password: "another.pass",
          nonce: "abcdef", data: ["custom_key": "custom_value", "camelKey": 1]),
        redirectTo: URL(string: "myapp://callback"))

      #expect(client.body(at: 0) == client.body(at: 1))
      #expect(client.body(at: 0)?["code_challenge"] as? String == "challenge")
      #expect(
        client.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer accesstoken")
    }

    @Test
    func updateUserSendsTheCurrentPassword() async throws {
      mock("user", .put, data: MockData.user)
      let client = V3TestClient()
      client.storeSession()

      try await client.sut.updateUser(UpdateUser(password: "new", currentPassword: "old"))

      #expect(client.lastBody == ["password": "new", "current_password": "old"])
    }

    @available(*, deprecated, message: "Compares with the deprecated v2 method.")
    @Test
    func resetPasswordSendsTheV2Request() async throws {
      mock("recover")
      let client = V3TestClient()

      try await client.sut.resetPassword(
        email: "example@mail.com",
        options: ResetPasswordOptions(
          redirectTo: URL(string: "myapp://reset"), captchaToken: "captcha"))
      try await client.sut.resetPasswordForEmail(
        "example@mail.com", redirectTo: URL(string: "myapp://reset"), captchaToken: "captcha")

      #expect(client.body(at: 0) == client.body(at: 1))
      #expect(client.query(at: 0) == client.query(at: 1))
      #expect(client.query(at: 0)["redirect_to"] == "myapp://reset")
      #expect(client.body(at: 0)?["email"] as? String == "example@mail.com")

      try await client.sut.resetPassword(email: "example@mail.com")
      #expect(client.query()["redirect_to"] == nil)
    }

    @available(*, deprecated, message: "Compares with the deprecated v2 method.")
    @Test
    func linkIdentityWithIDTokenSendsTheV2Body() async throws {
      mock("token", data: MockData.session)
      let client = V3TestClient()
      client.storeSession()

      try await client.sut.linkIdentity(
        idToken: IDTokenCredentials(provider: .google, idToken: "id-token", nonce: "nonce"))
      #expect(
        client.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer accesstoken")

      client.storeSession()
      try await client.sut.linkIdentityWithIdToken(
        credentials: OpenIDConnectCredentials(
          provider: .google, idToken: "id-token", nonce: "nonce"))

      #expect(client.body(at: 0) == client.body(at: 1))
      #expect(client.body(at: 0)?["link_identity"] as? Bool == true)
    }

    @Test
    func userUsesTheSessionOrTheGivenToken() async throws {
      mock("user", .get, data: MockData.user)
      let client = V3TestClient()
      client.storeSession()

      let user = try await client.sut.user()
      #expect(user.id == User(fromMockNamed: "user").id)
      #expect(
        client.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer accesstoken")

      _ = try await client.sut.user(jwt: "other-token")
      #expect(
        client.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer other-token")
    }

    @Test
    func refreshSession() async throws {
      mock("token", data: MockData.session)
      let client = V3TestClient()

      await #expect(throws: AuthError.sessionMissing) {
        try await client.sut.refreshSession()
      }

      client.storeSession()
      let accessToken = try await client.sut.refreshSession().accessToken
      #expect(accessToken == Session(fromMockNamed: "session").accessToken)
      #expect(client.lastBody?["refresh_token"] as? String == Session.validSession.refreshToken)
    }

    @available(*, deprecated, message: "Covers the deprecated session property.")
    @Test
    func sessionMethodLivesNextToTheSessionProperty() async throws {
      let client = V3TestClient()
      client.storeSession()

      let fromMethod = try await client.sut.session()
      #expect(fromMethod == .validSession)

      // No type annotation: `.accessToken` compiles only when `session` is still the property.
      let fromProperty = try await client.sut.session
      #expect(fromProperty.accessToken == fromMethod.accessToken)
      #expect(try await client.sut.session.user.id == fromMethod.user.id)
    }

    @available(*, deprecated, message: "Covers the deprecated isExpired property.")
    @Test
    func isExpiredAtDateWithLeeway() {
      var session = Session.validSession
      let expiry = Date(timeIntervalSince1970: 2_000_000_000)
      session.expiresAt = expiry.timeIntervalSince1970

      #expect(!session.isExpired(at: expiry.addingTimeInterval(-31)))
      #expect(session.isExpired(at: expiry.addingTimeInterval(-29)))
      #expect(!session.isExpired(at: expiry.addingTimeInterval(-1), leeway: .zero))
      #expect(session.isExpired(at: expiry, leeway: .zero) == false)
      #expect(session.isExpired(at: expiry.addingTimeInterval(1), leeway: .zero))
      #expect(session.isExpired(at: expiry.addingTimeInterval(-90), leeway: .seconds(120)))

      // The property and the key path still resolve.
      let expired: Bool = Session.expiredSession.isExpired
      #expect(expired)
      #expect(Session.expiredSession.isExpired())
      #expect([Session.expiredSession].map(\.isExpired) == [true])
    }
  }
}
