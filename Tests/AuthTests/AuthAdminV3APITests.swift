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
  struct AuthAdminV3APITests {
    let userID = UUID(uuidString: "859F402D-B3DE-4105-A1B9-932836D9193B")!
    let oauthClientJSON = Data(
      """
      {
        "client_id": "859F402D-B3DE-4105-A1B9-932836D9193B",
        "client_name": "App",
        "client_type": "confidential",
        "token_endpoint_auth_method": "client_secret_basic",
        "registration_type": "manual",
        "redirect_uris": ["https://example.com/callback"],
        "grant_types": ["authorization_code"],
        "response_types": ["code"],
        "created_at": "2025-01-01T00:00:00.000Z",
        "updated_at": "2025-01-01T00:00:00.000Z"
      }
      """.utf8)

    init() {
      Mocker.removeAll()
    }

    @available(*, deprecated, message: "Compares with the deprecated v2 method.")
    @Test
    func userByID() async throws {
      mock("admin/users/\(userID)", .get, data: MockData.user)
      let client = V3TestClient()

      let user = try await client.sut.admin.user(id: userID)
      let old = try await client.sut.admin.getUserById(userID)

      #expect(user == old)
      #expect(client.requests.value[0].url == client.requests.value[1].url)
    }

    @available(*, deprecated, message: "Compares with the deprecated v2 method.")
    @Test
    func createUserSendsTheV2Body() async throws {
      mock("admin/users", data: MockData.user)
      let client = V3TestClient()

      try await client.sut.admin.createUser(
        AdminCreateUser(
          id: userID, email: "user@example.com", phone: "+15555550100", password: "secret",
          passwordHash: "hash", confirmsEmail: true, confirmsPhone: false, role: "editor",
          userMetadata: ["name": "User"], appMetadata: ["plan": "pro"],
          banDuration: .seconds(3600)))
      try await client.sut.admin.createUser(
        attributes: AdminUserAttributes(
          appMetadata: ["plan": "pro"], banDuration: "3600s", email: "user@example.com",
          emailConfirm: true, id: userID.uuidString, password: "secret", passwordHash: "hash",
          phone: "+15555550100", phoneConfirm: false, role: "editor",
          userMetadata: ["name": "User"]))

      #expect(client.body(at: 0) == client.body(at: 1))
      #expect(client.body(at: 0)?["email_confirm"] as? Bool == true)
      #expect(client.body(at: 0)?["ban_duration"] as? String == "3600s")
    }

    @available(*, deprecated, message: "Compares with the deprecated v2 method.")
    @Test
    func updateUserSendsTheV2Body() async throws {
      mock("admin/users/\(userID)", .put, data: MockData.user)
      let client = V3TestClient()

      try await client.sut.admin.updateUser(
        id: userID,
        AdminUpdateUser(
          email: "user@example.com", confirmsEmail: true, userMetadata: ["name": "User"],
          banDuration: .zero))
      try await client.sut.admin.updateUserById(
        userID,
        attributes: AdminUserAttributes(
          banDuration: "none", email: "user@example.com", emailConfirm: true,
          userMetadata: ["name": "User"]))

      #expect(client.body(at: 0) == client.body(at: 1))
      #expect(client.body(at: 0)?["ban_duration"] as? String == "none")
      #expect(client.requests.value[0].url == client.requests.value[1].url)
    }

    @Test
    func banDurationEncoding() throws {
      func banDuration(_ duration: Duration) throws -> String? {
        let data = try JSONEncoder().encode(AdminUpdateUser(banDuration: duration))
        return try (JSONSerialization.jsonObject(with: data) as? [String: Any])?["ban_duration"]
          as? String
      }

      #expect(try banDuration(.seconds(90)) == "90s")
      #expect(try banDuration(.milliseconds(1500)) == "1500000000ns")
      #expect(try banDuration(.zero) == "none")
      #expect(try JSONEncoder().encode(AdminUpdateUser()) == Data("{}".utf8))
    }

    @available(*, deprecated, message: "Compares with the deprecated v2 method.")
    @Test
    func deleteUser() async throws {
      mock("admin/users/\(userID)", .delete)
      let client = V3TestClient()

      try await client.sut.admin.deleteUser(id: userID, softDelete: true)
      try await client.sut.admin.deleteUser(id: userID, shouldSoftDelete: true)
      #expect(client.body(at: 0) == client.body(at: 1))
      #expect(client.body(at: 0) == ["should_soft_delete": true])

      // The short v2 call still compiles and sends the same request.
      try await client.sut.admin.deleteUser(id: userID)
      #expect(client.lastBody == ["should_soft_delete": false])
    }

    @available(*, deprecated, message: "Compares with the deprecated v2 method.")
    @Test
    func inviteUser() async throws {
      mock("invite", data: MockData.user)
      let client = V3TestClient()

      try await client.sut.admin.inviteUser(
        email: "user@example.com", userMetadata: ["name": "User"],
        redirectTo: URL(string: "myapp://invite"))
      try await client.sut.admin.inviteUserByEmail(
        "user@example.com", data: ["name": "User"], redirectTo: URL(string: "myapp://invite"))

      #expect(client.body(at: 0) == client.body(at: 1))
      #expect(client.query(at: 0) == client.query(at: 1))
      #expect(client.query(at: 0)["redirect_to"] == "myapp://invite")
    }

    @available(*, deprecated, message: "Compares with the deprecated v2 method.")
    @Test
    func listUsers() async throws {
      mock("admin/users", .get, data: MockData.listUsersResponse)
      let client = V3TestClient()

      let page = try await client.sut.admin.listUsers(page: 2, pageSize: 10)
      let old = try await client.sut.admin.listUsers(params: PageParams(page: 2, perPage: 10))

      #expect(page == old)
      #expect(client.query(at: 0) == ["page": "2", "per_page": "10"])
      #expect(client.query(at: 0) == client.query(at: 1))

      // The short v2 call keeps its result type and its request.
      let short = try await client.sut.admin.listUsers()
      #expect(short.users.count == page.users.count)
      #expect(short.aud == page.audience)
      #expect(client.query() == ["page": "", "per_page": ""])
    }

    @available(*, deprecated, message: "Compares with the deprecated v2 method.")
    @Test
    func generateLink() async throws {
      mock(
        "admin/generate_link",
        data: Data(
          """
          {
            "action_link": "https://example.com/verify",
            "email_otp": "123456",
            "hashed_token": "hash",
            "redirect_to": "https://example.com",
            "verification_type": "invite",
            "id": "859F402D-B3DE-4105-A1B9-932836D9193B",
            "aud": "authenticated",
            "created_at": "2025-01-01T00:00:00.000Z",
            "updated_at": "2025-01-01T00:00:00.000Z"
          }
          """.utf8))
      let client = V3TestClient()

      let response = try await client.sut.admin.generateLink(
        .invite(
          email: "user@example.com", userMetadata: ["name": "User"],
          redirectTo: URL(string: "myapp://invite")))
      #expect(response.properties.verificationType == .invite)

      _ = try await client.sut.admin.generateLink(
        params: .invite(
          email: "user@example.com", data: ["name": "User"],
          redirectTo: URL(string: "myapp://invite")))

      #expect(client.body(at: 0) == client.body(at: 1))
      #expect(client.query(at: 0) == client.query(at: 1))
      #expect((client.body(at: 0)?["data"] as? NSDictionary) == ["name": "User"])
    }

    @Test
    func generateLinkFactoriesResolveWithShortCalls() {
      let invite: GenerateLink = .invite(email: "user@example.com")
      #expect(invite.body.type == .invite)

      let magicLink = GenerateLinkParams.magicLink(email: "user@example.com")
      #expect(magicLink.body.type == .magiclink)

      let signUp = GenerateLink.signUp(
        email: "user@example.com", password: "secret", userMetadata: ["name": "User"])
      #expect(signUp.body.data == ["name": "User"])
    }

    @available(*, deprecated, message: "Covers the deprecated v2 overload.")
    @Test
    func listClients() async throws {
      Mock(
        url: clientURL.appendingPathComponent("admin/oauth/clients"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data(#"{"clients": ["#.utf8) + oauthClientJSON + Data("]}".utf8)]
      ).register()
      let client = V3TestClient()

      let clients: [OAuthClient] = try await client.sut.admin.oauth.listClients()

      #expect(clients.map(\.clientID) == [userID])
      #expect(client.query().isEmpty)
    }

    @available(*, deprecated, message: "Covers the deprecated v2 overload.")
    @Test
    func listClientsShortCallKeepsTheV2Result() async throws {
      Mock(
        url: clientURL.appendingPathComponent("admin/oauth/clients"),
        ignoreQuery: true,
        statusCode: 200,
        data: [
          .get: Data(#"{"aud": "authenticated", "clients": ["#.utf8) + oauthClientJSON
            + Data("]}".utf8)
        ]
      ).register()
      let client = V3TestClient()

      // No type annotation: `.clients` exists only on the v2 result.
      let response = try await client.sut.admin.oauth.listClients()

      #expect(response.clients.count == 1)
    }

    @Test
    func listClientsDecodesAnEmptyBody() async throws {
      mock("admin/oauth/clients", .get, data: Data("{}".utf8))
      let client = V3TestClient()

      let clients: [OAuthClient] = try await client.sut.admin.oauth.listClients()

      #expect(clients.isEmpty)
    }

    @available(*, deprecated, message: "Compares with the deprecated v2 method.")
    @Test
    func createAndUpdateClientSendTheV2Body() async throws {
      mock("admin/oauth/clients", data: oauthClientJSON)
      mock("admin/oauth/clients/\(userID)", .put, data: oauthClientJSON)
      let client = V3TestClient()

      try await client.sut.admin.oauth.createClient(
        CreateOAuthClient(
          clientName: "App", clientURI: URL(string: "https://example.com"),
          redirectURIs: [URL(string: "https://example.com/callback")!],
          grantTypes: [.authorizationCode], responseTypes: [.code], scope: "openid"))
      try await client.sut.admin.oauth.createClient(
        params: CreateOAuthClientParams(
          clientName: "App", clientUri: "https://example.com",
          redirectUris: ["https://example.com/callback"], grantTypes: [.authorizationCode],
          responseTypes: [.code], scope: "openid"))
      #expect(client.body(at: 0) == client.body(at: 1))
      #expect(client.body(at: 0)?["redirect_uris"] as? [String] == ["https://example.com/callback"])

      let updated = try await client.sut.admin.oauth.updateClient(
        id: userID,
        UpdateOAuthClient(
          clientName: "New", clientURI: URL(string: "https://example.com"),
          logoURI: URL(string: "https://example.com/logo.png"),
          redirectURIs: [URL(string: "https://example.com/callback")!],
          grantTypes: [.refreshToken]))
      _ = try await client.sut.admin.oauth.updateClient(
        clientId: userID,
        params: UpdateOAuthClientParams(
          clientName: "New", clientUri: "https://example.com",
          logoUri: "https://example.com/logo.png",
          redirectUris: ["https://example.com/callback"], grantTypes: [.refreshToken]))
      #expect(updated.clientID == userID)
      #expect(client.body(at: 2) == client.body(at: 3))
      #expect(client.requests.value[2].url == client.requests.value[3].url)
    }

    @Test
    func clientByIDDeleteAndRegenerate() async throws {
      mock("admin/oauth/clients/\(userID)", .get, data: oauthClientJSON)
      mock("admin/oauth/clients/\(userID)", .delete)
      mock("admin/oauth/clients/\(userID)/regenerate_secret", data: oauthClientJSON)
      let client = V3TestClient()

      #expect(try await client.sut.admin.oauth.client(id: userID).clientID == userID)

      try await client.sut.admin.oauth.deleteClient(id: userID)
      #expect(client.lastRequest?.httpMethod == "DELETE")

      try await client.sut.admin.oauth.regenerateClientSecret(id: userID)
      #expect(client.lastRequest?.url?.lastPathComponent == "regenerate_secret")
    }

    @Test
    func oauthServerMethods() async throws {
      let redirect = Data(#"{"redirect_url": "https://example.com/callback?code=1"}"#.utf8)
      mock("oauth/authorizations/abc123", .get, data: redirect)
      mock("oauth/authorizations/abc123/consent", data: redirect)
      mock("user/oauth/grants", .delete)
      let client = V3TestClient()
      client.storeSession()
      let expected = OAuthRedirect(
        redirectURL: URL(string: "https://example.com/callback?code=1")!)

      let result: OAuthAuthorizationDetailsResult =
        try await client.sut.oauthServer.authorizationDetails(id: "abc123")
      #expect(result == .redirect(expected))

      #expect(try await client.sut.oauthServer.approveAuthorization(id: "abc123") == expected)
      #expect(client.lastBody == ["action": "approve"])

      #expect(try await client.sut.oauthServer.denyAuthorization(id: "abc123") == expected)
      #expect(client.lastBody == ["action": "deny"])

      try await client.sut.oauthServer.revokeGrant(clientID: userID)
      #expect(client.query() == ["client_id": userID.uuidString])
    }
  }
}
