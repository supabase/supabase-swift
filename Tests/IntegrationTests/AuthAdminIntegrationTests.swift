//
//  AuthAdminIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 03/11/26.
//

import Foundation
import TestHelpers
import Testing

@testable import Auth

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct AuthAdminIntegrationTests {
  let admin = AuthClientIntegrationTests.makeAdminClient()

  // The server resolves each provider URL's host before it saves the provider, so the URLs need
  // a host that resolves.
  @Test
  func customProviderLifecycle() async throws {
    let identifier = "custom:swift-\(UUID().uuidString.prefix(8).lowercased())"

    var params = CreateCustomProviderParams.oauth2(
      identifier: identifier,
      name: "Swift Integration",
      clientID: "client-id",
      clientSecret: "client-secret",
      authorizationURL: URL(string: "https://example.com/authorize")!,
      tokenURL: URL(string: "https://example.com/token")!,
      userinfoURL: URL(string: "https://example.com/userinfo")!
    )
    params.scopes = ["openid", "email"]
    params.customClaimsAllowlist = ["groups"]

    let created = try await admin.customProviders.create(params)
    do {
      try await exerciseProvider(created, identifier: identifier)
    } catch {
      try? await admin.customProviders.delete(identifier: identifier)
      throw error
    }

    try await admin.customProviders.delete(identifier: identifier)

    await #expect(throws: AuthError.self) {
      try await admin.customProviders.provider(identifier: identifier)
    }
  }

  private func exerciseProvider(_ created: CustomProvider, identifier: String) async throws {
    #expect(created.identifier == identifier)
    #expect(created.providerType == .oauth2)
    #expect(created.customClaimsAllowlist == ["groups"])

    let fetched = try await admin.customProviders.provider(identifier: identifier)
    #expect(fetched.id == created.id)

    let oauth2Providers = try await admin.customProviders.list(type: .oauth2)
    #expect(oauth2Providers.contains { $0.id == created.id })
    let oidcProviders = try await admin.customProviders.list(type: .oidc)
    #expect(!oidcProviders.contains { $0.id == created.id })

    let updated = try await admin.customProviders.update(
      identifier: identifier,
      params: UpdateCustomProviderParams(name: "Renamed", customClaimsAllowlist: ["groups", "org"])
    )
    #expect(updated.name == "Renamed")
    #expect(updated.customClaimsAllowlist == ["groups", "org"])
    #expect(updated.scopes == ["openid", "email"])
  }

  @Test
  func banDurationBansAndLifts() async throws {
    let email = "ban-\(UUID().uuidString.prefix(8).lowercased())@example.com"
    let password = "the.pass.\(UUID().uuidString)"
    let id = UUID()

    let user = try await admin.createUser(
      AdminUserAttributes(email: email, confirmsEmail: true, id: id, password: password))
    #expect(user.id == id)

    do {
      try await admin.updateUser(
        id: id, attributes: AdminUserAttributes(banDuration: .seconds(3_600)))
      await #expect(throws: AuthError.self) {
        try await AuthClientIntegrationTests.makeClient().signIn(email: email, password: password)
      }

      try await admin.updateUser(id: id, attributes: AdminUserAttributes(banDuration: .zero))
      _ = try await AuthClientIntegrationTests.makeClient().signIn(email: email, password: password)
    } catch {
      try? await admin.deleteUser(id: id)
      throw error
    }

    try await admin.deleteUser(id: id)
  }
}
