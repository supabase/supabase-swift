//
//  AuthAdminSignOutTests.swift
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
  struct AuthAdminSignOutTests {
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
        fetch: { request in
          try await session.data(for: request)
        }
      )

      return AuthClient(configuration: configuration)
    }

    @Test
    func signOutDefaultScope() async throws {
      Mock(
        url: clientURL.appendingPathComponent("logout"),
        ignoreQuery: true,
        statusCode: 204,
        data: [.post: Data()]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Authorization: Bearer users.access.token" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: supabase.publishable.key" \
        	"http://localhost:54321/auth/v1/logout?scope=global"
        """#
      }
      .register()

      let sut = makeSUT()

      try await sut.admin.signOut(jwt: "users.access.token")
    }

    @Test
    func signOutLocalScope() async throws {
      Mock(
        url: clientURL.appendingPathComponent("logout"),
        ignoreQuery: true,
        statusCode: 204,
        data: [.post: Data()]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Authorization: Bearer users.access.token" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: supabase.publishable.key" \
        	"http://localhost:54321/auth/v1/logout?scope=local"
        """#
      }
      .register()

      let sut = makeSUT()

      try await sut.admin.signOut(jwt: "users.access.token", scope: .local)
    }

    @Test
    func signOutOthersScope() async throws {
      Mock(
        url: clientURL.appendingPathComponent("logout"),
        ignoreQuery: true,
        statusCode: 204,
        data: [.post: Data()]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Authorization: Bearer users.access.token" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: supabase.publishable.key" \
        	"http://localhost:54321/auth/v1/logout?scope=others"
        """#
      }
      .register()

      let sut = makeSUT()

      try await sut.admin.signOut(jwt: "users.access.token", scope: .others)
    }

    @Test
    func signOutPropagatesError() async throws {
      let errorData = """
        {
          "error": "invalid_token",
          "error_description": "The access token is invalid"
        }
        """.data(using: .utf8)!

      Mock(
        url: clientURL.appendingPathComponent("logout"),
        ignoreQuery: true,
        statusCode: 401,
        data: [.post: errorData]
      )
      .register()

      let sut = makeSUT()

      do {
        try await sut.admin.signOut(jwt: "invalid.access.token")
        Issue.record("Expected signOut to throw")
      } catch let error as AuthError {
        guard case .api = error else {
          Issue.record("Expected AuthError.api, got \(error)")
          return
        }
      }
    }
  }
}
