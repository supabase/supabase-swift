//
//  AuthMFARecoveryCodesTests.swift
//
//
//  Created by Ranbir Singh on 23/09/26.
//

import CustomDump
import Foundation
import Mocker
import TestHelpers
import Testing

@testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension AuthMockerTests {
  @Suite(.mockerSerialized)
  struct AuthMFARecoveryCodesTests {
    let factorId = "0d3aa138-da96-4aea-8d9e-c8b0e1234567"

    let storage = InMemoryLocalStorage()

    private var recoveryCodesURL: URL {
      clientURL.appendingPathComponent("factors/recovery-codes")
    }

    private func makeSUT() -> AuthClient {
      let sessionConfiguration = URLSessionConfiguration.default
      sessionConfiguration.protocolClasses = [MockingURLProtocol.self]
      let session = URLSession(configuration: sessionConfiguration)

      let configuration = AuthClient.Configuration(
        url: clientURL,
        headers: ["apikey": "supabase.publishable.key"],
        localStorage: storage,
        http: .init(transport: URLSessionTransport(session: session)))

      return AuthClient(configuration: configuration)
    }

    @Test
    func status() async throws {
      Mock(
        url: recoveryCodesURL,
        statusCode: 200,
        data: [
          .get: Data(
            """
            {
              "id": "\(factorId)",
              "total": 10,
              "remaining": 7
            }
            """.utf8
          )
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Authorization: Bearer accesstoken" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: supabase.publishable.key" \
        	"http://localhost:54321/auth/v1/factors/recovery-codes"
        """#
      }
      .register()

      let sut = makeSUT()
      Dependencies[sut.clientID].sessionStorage.store(.valid)

      let response = try await sut.mfa.recoveryCodes.status()

      expectNoDifference(
        response,
        AuthMFARecoveryCodesStatusResponse(id: factorId, total: 10, remaining: 7)
      )
    }

    @Test
    func generateSendsTheFriendlyName() async throws {
      Mock(
        url: recoveryCodesURL,
        statusCode: 200,
        data: [
          .post: Data(
            """
            {
              "id": "\(factorId)",
              "friendly_name": "Backup codes",
              "total": 2,
              "codes": ["K4M9-X7QP-2AB8-HT3Z", "R7TW-9PLN-4CD2-KS6V"]
            }
            """.utf8
          )
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Authorization: Bearer accesstoken" \
        	--header "Content-Length: 32" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: supabase.publishable.key" \
        	--data "{\"friendly_name\":\"Backup codes\"}" \
        	"http://localhost:54321/auth/v1/factors/recovery-codes"
        """#
      }
      .register()

      let sut = makeSUT()
      Dependencies[sut.clientID].sessionStorage.store(.valid)

      let response = try await sut.mfa.recoveryCodes.generate(friendlyName: "Backup codes")

      expectNoDifference(response.id, factorId)
      expectNoDifference(response.friendlyName, "Backup codes")
      expectNoDifference(response.total, 2)
      expectNoDifference(response.codes, ["K4M9-X7QP-2AB8-HT3Z", "R7TW-9PLN-4CD2-KS6V"])
    }

    @Test
    func generateWithoutAFriendlyNameSendsNoBody() async throws {
      Mock(
        url: recoveryCodesURL,
        statusCode: 200,
        data: [
          .post: Data(
            """
            {
              "id": "\(factorId)",
              "friendly_name": "Recovery codes",
              "total": 1,
              "codes": ["K4M9-X7QP-2AB8-HT3Z"]
            }
            """.utf8
          )
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Authorization: Bearer accesstoken" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: supabase.publishable.key" \
        	"http://localhost:54321/auth/v1/factors/recovery-codes"
        """#
      }
      .register()

      let sut = makeSUT()
      Dependencies[sut.clientID].sessionStorage.store(.valid)

      let response = try await sut.mfa.recoveryCodes.generate()

      expectNoDifference(response.friendlyName, "Recovery codes")
    }

    @Test
    func regenerate() async throws {
      Mock(
        url: recoveryCodesURL.appendingPathComponent("regenerate"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {
              "id": "\(factorId)",
              "friendly_name": "Backup codes",
              "total": 1,
              "codes": ["W2QH-6BTX-8NM4-JY5R"]
            }
            """.utf8
          )
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Authorization: Bearer accesstoken" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: supabase.publishable.key" \
        	"http://localhost:54321/auth/v1/factors/recovery-codes/regenerate"
        """#
      }
      .register()

      let sut = makeSUT()
      Dependencies[sut.clientID].sessionStorage.store(.valid)

      let response = try await sut.mfa.recoveryCodes.regenerate()

      expectNoDifference(response.codes, ["W2QH-6BTX-8NM4-JY5R"])
    }

    @Test
    func verifyStoresTheUpgradedSession() async throws {
      Mock(
        url: recoveryCodesURL.appendingPathComponent("verify"),
        statusCode: 200,
        data: [.post: MockData.session]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Authorization: Bearer accesstoken" \
        	--header "Content-Length: 30" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: supabase.publishable.key" \
        	--data "{\"code\":\"K4M9-X7QP-2AB8-HT3Z\"}" \
        	"http://localhost:54321/auth/v1/factors/recovery-codes/verify"
        """#
      }
      .register()

      let sut = makeSUT()
      Dependencies[sut.clientID].sessionStorage.store(.valid)

      let response = try await sut.mfa.recoveryCodes.verify(code: "K4M9-X7QP-2AB8-HT3Z")

      expectNoDifference(response.refreshToken, "GGduTeu95GraIXQ56jppkw")
      expectNoDifference(
        Dependencies[sut.clientID].sessionStorage.get()?.refreshToken,
        "GGduTeu95GraIXQ56jppkw"
      )
    }

    @Test
    func unenroll() async throws {
      Mock(
        url: recoveryCodesURL,
        statusCode: 200,
        data: [.delete: Data(#"{"id":"\#(factorId)"}"#.utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request DELETE \
        	--header "Authorization: Bearer accesstoken" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: supabase.publishable.key" \
        	"http://localhost:54321/auth/v1/factors/recovery-codes"
        """#
      }
      .register()

      let sut = makeSUT()
      Dependencies[sut.clientID].sessionStorage.store(.valid)

      let id = try await sut.mfa.recoveryCodes.unenroll().id

      expectNoDifference(id, factorId)
    }
  }
}
