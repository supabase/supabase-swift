//
//  AuthAdminGenerateLinkTests.swift
//
//

import ConcurrencyExtras
import CustomDump
import Foundation
import Helpers
import InlineSnapshotTesting
import TestHelpers
import Testing

@testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct AuthAdminGenerateLinkTests {
  let transport = RecordingTransport()

  private func responseData(
    verificationType: String,
    redirectTo: String? = "https://example.com"
  ) throws -> Data {
    let user = User(fromMockNamed: "user")
    let encoder = AuthClient.Configuration.jsonEncoder
    let userData = try encoder.encode(user)
    var json = try JSONSerialization.jsonObject(with: userData, options: []) as! [String: Any]

    json["action_link"] =
      "https://example.com/auth/v1/verify?type=\(verificationType)&token=hashed_token&redirect_to=https://example.com"
    json["email_otp"] = "123456"
    json["hashed_token"] = "hashed_token"
    json["redirect_to"] = redirectTo
    json["verification_type"] = verificationType

    return try JSONSerialization.data(withJSONObject: json)
  }

  @Test
  func generateLinkSignUp() async throws {
    transport.stub(.post, "admin/generate_link", data: try responseData(verificationType: "signup"))

    let sut = AuthAdminClient.testing(http: transport)

    let link = try await sut.generateLink(
      .signUp(
        email: "test@example.com",
        password: "password",
        userMetadata: ["full_name": "John Doe"]
      )
    )

    expectNoDifference(link.properties.verificationType, .signup)
    expectNoDifference(link.properties.hashedToken, "hashed_token")
    expectNoDifference(link.properties.redirectTo, URL(string: "https://example.com")!)
    expectNoDifference(link.user.email, "guilherme@grds.dev")
  }

  @Test
  func generateLinkMagicLink() async throws {
    transport.stub(
      .post, "admin/generate_link", data: try responseData(verificationType: "magiclink"))

    let sut = AuthAdminClient.testing(http: transport)

    let link = try await sut.generateLink(
      .magicLink(email: "test@example.com")
    )

    expectNoDifference(link.properties.verificationType, .magiclink)
  }

  @Test
  func generateLinkRecovery() async throws {
    transport.stub(
      .post, "admin/generate_link", data: try responseData(verificationType: "recovery"))

    let sut = AuthAdminClient.testing(http: transport)

    let link = try await sut.generateLink(
      .recovery(email: "test@example.com")
    )

    expectNoDifference(link.properties.verificationType, .recovery)
  }

  @Test
  func generateLinkInvite() async throws {
    transport.stub(.post, "admin/generate_link", data: try responseData(verificationType: "invite"))

    let sut = AuthAdminClient.testing(http: transport)

    let link = try await sut.generateLink(
      .invite(email: "test@example.com")
    )

    expectNoDifference(link.properties.verificationType, .invite)
  }

  @Test
  func generateLinkEmailChangeNew() async throws {
    transport.stub(
      .post, "admin/generate_link", data: try responseData(verificationType: "email_change_new"))

    let sut = AuthAdminClient.testing(http: transport)

    let link = try await sut.generateLink(
      .emailChangeNew(email: "test@example.com", newEmail: "new@example.com")
    )

    expectNoDifference(link.properties.verificationType, .emailChangeNew)
  }

  @Test
  func generateLinkWithoutRedirectTo() async throws {
    transport.stub(
      .post, "admin/generate_link",
      data: try responseData(verificationType: "magiclink", redirectTo: nil))

    let sut = AuthAdminClient.testing(http: transport)

    let link = try await sut.generateLink(.magicLink(email: "test@example.com"))

    #expect(link.properties.redirectTo == nil)
    #expect(link.user.id == User(fromMockNamed: "user").id)
  }
}
