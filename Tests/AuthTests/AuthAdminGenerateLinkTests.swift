//
//  AuthAdminGenerateLinkTests.swift
//
//

import ConcurrencyExtras
import CustomDump
import Foundation
import Helpers
import InlineSnapshotTesting
import Mocker
import TestHelpers
import Testing

@testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension AuthMockerTests {
  @Suite(.mockerSerialized)
  struct AuthAdminGenerateLinkTests {
    let storage = InMemoryLocalStorage()

    private func makeSUT() -> AuthClient {
      let sessionConfiguration = URLSessionConfiguration.default
      sessionConfiguration.protocolClasses = [MockingURLProtocol.self]
      let session = URLSession(configuration: sessionConfiguration)

      let configuration = AuthClient.Configuration(
        url: clientURL,
        headers: [
          "apikey": "supabase.publishable.key",
          "Authorization": "Bearer supabase.secret.key",
        ],
        localStorage: storage,
        logger: nil,
        fetch: { request in
          try await session.data(for: request)
        }
      )

      return AuthClient(configuration: configuration)
    }

    /// Builds a flat JSON object mirroring what the `/admin/generate_link` endpoint returns:
    /// the user's own fields merged with the generate-link-specific properties.
    private func responseData(verificationType: String) throws -> Data {
      let user = User(fromMockNamed: "user")
      let encoder = AuthClient.Configuration.jsonEncoder
      let userData = try encoder.encode(user)
      var json = try JSONSerialization.jsonObject(with: userData, options: []) as! [String: Any]

      json["action_link"] =
        "https://example.com/auth/v1/verify?type=\(verificationType)&token=hashed_token&redirect_to=https://example.com"
      json["email_otp"] = "123456"
      json["hashed_token"] = "hashed_token"
      json["redirect_to"] = "https://example.com"
      json["verification_type"] = verificationType

      return try JSONSerialization.data(withJSONObject: json)
    }

    @Test
    func generateLinkSignUp() async throws {
      Mock(
        url: clientURL.appendingPathComponent("admin/generate_link"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: try responseData(verificationType: "signup")]
      )
      .register()

      let sut = makeSUT()

      let link = try await sut.admin.generateLink(
        params: .signUp(
          email: "test@example.com",
          password: "password",
          data: ["full_name": "John Doe"]
        )
      )

      expectNoDifference(link.properties.verificationType, .signup)
      expectNoDifference(link.properties.hashedToken, "hashed_token")
      expectNoDifference(link.properties.redirectTo, URL(string: "https://example.com")!)
      expectNoDifference(link.user.email, "guilherme@grds.dev")
    }

    @Test
    func generateLinkMagicLink() async throws {
      Mock(
        url: clientURL.appendingPathComponent("admin/generate_link"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: try responseData(verificationType: "magiclink")]
      )
      .register()

      let sut = makeSUT()

      let link = try await sut.admin.generateLink(
        params: .magicLink(email: "test@example.com")
      )

      expectNoDifference(link.properties.verificationType, .magiclink)
    }

    @Test
    func generateLinkRecovery() async throws {
      Mock(
        url: clientURL.appendingPathComponent("admin/generate_link"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: try responseData(verificationType: "recovery")]
      )
      .register()

      let sut = makeSUT()

      let link = try await sut.admin.generateLink(
        params: .recovery(email: "test@example.com")
      )

      expectNoDifference(link.properties.verificationType, .recovery)
    }

    @Test
    func generateLinkInvite() async throws {
      Mock(
        url: clientURL.appendingPathComponent("admin/generate_link"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: try responseData(verificationType: "invite")]
      )
      .register()

      let sut = makeSUT()

      let link = try await sut.admin.generateLink(
        params: .invite(email: "test@example.com")
      )

      expectNoDifference(link.properties.verificationType, .invite)
    }

    @Test
    func generateLinkEmailChangeNew() async throws {
      Mock(
        url: clientURL.appendingPathComponent("admin/generate_link"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: try responseData(verificationType: "email_change_new")]
      )
      .register()

      let sut = makeSUT()

      let link = try await sut.admin.generateLink(
        params: .emailChangeNew(email: "test@example.com", newEmail: "new@example.com")
      )

      expectNoDifference(link.properties.verificationType, .emailChangeNew)
    }
  }
}
