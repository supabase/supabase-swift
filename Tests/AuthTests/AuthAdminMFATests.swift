//
//  AuthAdminMFATests.swift
//
//
//  Created by Ranbir Singh on 16/09/26.
//

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
  struct AuthAdminMFATests {
    let userId = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
    let factorId = UUID(uuidString: "0d3aa138-da96-4aea-8d9e-c8b0e1234567")!

    @Test
    func listFactors() async throws {
      let responseData = """
        [
          {
            "id": "\(factorId)",
            "friendly_name": "My Phone",
            "factor_type": "totp",
            "status": "verified",
            "created_at": "2024-01-01T00:00:00.000Z",
            "updated_at": "2024-01-02T00:00:00.000Z"
          }
        ]
        """.data(using: .utf8)!

      Mock(
        url: clientURL.appendingPathComponent("admin/users/\(userId)/factors"),
        statusCode: 200,
        data: [.get: responseData]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Authorization: Bearer supabase.secret.key" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: supabase.secret.key" \
        	"http://localhost:54321/auth/v1/admin/users/E621E1F8-C36C-495A-93FC-0C247A3E6E5F/factors"
        """#
      }
      .register()

      let sut = AuthAdminClient.mocked()

      let factors = try await sut.mfa.listFactors(forUser: userId)

      #expect(factors.count == 1)
      #expect(factors.first?.id == factorId)
      #expect(factors.first?.friendlyName == "My Phone")
      #expect(factors.first?.factorType == "totp")
      #expect(factors.first?.status == .verified)
    }

    @Test
    func listFactorsWithNoFactorsEnrolled() async throws {
      Mock(
        url: clientURL.appendingPathComponent("admin/users/\(userId)/factors"),
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .register()

      let sut = AuthAdminClient.mocked()

      #expect(try await sut.mfa.listFactors(forUser: userId).isEmpty)
    }

    @Test
    func listFactorsWithoutFriendlyName() async throws {
      let responseData = """
        [
          {
            "id": "\(factorId)",
            "factor_type": "phone",
            "status": "unverified",
            "created_at": "2024-01-01T00:00:00.000Z",
            "updated_at": "2024-01-02T00:00:00.000Z"
          }
        ]
        """.data(using: .utf8)!

      Mock(
        url: clientURL.appendingPathComponent("admin/users/\(userId)/factors"),
        statusCode: 200,
        data: [.get: responseData]
      )
      .register()

      let sut = AuthAdminClient.mocked()

      let factors = try await sut.mfa.listFactors(forUser: userId)

      #expect(factors.first?.friendlyName == nil)
      #expect(factors.first?.factorType == "phone")
    }

    @Test
    func deleteFactor() async throws {
      let responseData = """
        {
          "id": "\(factorId)",
          "friendly_name": "My Phone",
          "factor_type": "totp",
          "status": "verified",
          "created_at": "2024-01-01T00:00:00.000Z",
          "updated_at": "2024-01-02T00:00:00.000Z"
        }
        """.data(using: .utf8)!

      Mock(
        url: clientURL.appendingPathComponent("admin/users/\(userId)/factors/\(factorId)"),
        statusCode: 200,
        data: [.delete: responseData]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request DELETE \
        	--header "Authorization: Bearer supabase.secret.key" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: supabase.secret.key" \
        	"http://localhost:54321/auth/v1/admin/users/E621E1F8-C36C-495A-93FC-0C247A3E6E5F/factors/0D3AA138-DA96-4AEA-8D9E-C8B0E1234567"
        """#
      }
      .register()

      let sut = AuthAdminClient.mocked()

      try await sut.mfa.deleteFactor(id: factorId, forUser: userId)
    }
  }
}
