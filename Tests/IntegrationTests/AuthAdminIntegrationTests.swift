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

    var params = CreateCustomProvider.oauth2(
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
      UpdateCustomProvider(name: "Renamed", customClaimsAllowlist: ["groups", "org"])
    )
    #expect(updated.name == "Renamed")
    #expect(updated.customClaimsAllowlist == ["groups", "org"])
    #expect(updated.scopes == ["openid", "email"])
  }

  @Test
  func usersPagesThroughEveryUser() async throws {
    var ids: [UUID] = []
    for _ in 0..<3 {
      let email = "paging-\(UUID().uuidString.prefix(8).lowercased())@example.com"
      ids.append(
        try await admin.createUser(AdminCreateUser(email: email, confirmsEmail: true)).id)
    }

    do {
      let pages = try await admin.users(pageSize: 1).pages.prefix(2).collect()
      // The three users above guarantee at least three pages of one.
      #expect(pages.map(\.users.count) == [1, 1])
      #expect(pages.map(\.nextPage) == [2, 3])
      let second = try await admin.users(pageSize: 1).page(after: 2)
      #expect(second.users.map(\.id) == pages[1].users.map(\.id))

      var seen: Set<UUID> = []
      for try await user in admin.users(pageSize: 100) {
        seen.insert(user.id)
      }
      #expect(seen.isSuperset(of: ids))
    } catch {
      for id in ids { try? await admin.deleteUser(id: id) }
      throw error
    }

    for id in ids { try await admin.deleteUser(id: id) }
  }

  @Test
  func banDurationBansAndLifts() async throws {
    let email = "ban-\(UUID().uuidString.prefix(8).lowercased())@example.com"
    let password = "the.pass.\(UUID().uuidString)"
    let id = UUID()

    let user = try await admin.createUser(
      AdminCreateUser(id: id, email: email, password: password, confirmsEmail: true))
    #expect(user.id == id)

    do {
      try await admin.updateUser(
        id: id, AdminUpdateUser(banDuration: .seconds(3_600)))
      await #expect(throws: AuthError.self) {
        try await AuthClientIntegrationTests.makeClient().signIn(email: email, password: password)
      }

      try await admin.updateUser(id: id, AdminUpdateUser(banDuration: .zero))
      _ = try await AuthClientIntegrationTests.makeClient().signIn(email: email, password: password)
    } catch {
      try? await admin.deleteUser(id: id)
      throw error
    }

    try await admin.deleteUser(id: id)
  }
}
