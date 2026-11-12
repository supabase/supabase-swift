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
  struct AuthMFAV3APITests {
    let factorID = UUID(uuidString: "0A1B2C3D-0000-4000-8000-000000000001")!
    let challengeID = UUID(uuidString: "0A1B2C3D-0000-4000-8000-000000000002")!
    var factorPath: String { "factors/0a1b2c3d-0000-4000-8000-000000000001" }

    init() {
      Mocker.removeAll()
    }

    private func signedInClient() -> V3TestClient {
      let client = V3TestClient()
      client.storeSession()
      return client
    }

    @available(*, deprecated, message: "Compares with the deprecated v2 method.")
    @Test
    func enrollTOTP() async throws {
      mock(
        "factors",
        data: Data(
          """
          {
            "id": "0a1b2c3d-0000-4000-8000-000000000001",
            "type": "totp",
            "friendly_name": "Authenticator",
            "totp": {"qr_code": "<svg/>", "secret": "SECRET", "uri": "otpauth://totp/x"}
          }
          """.utf8))
      let client = signedInClient()

      let enrollment = try await client.sut.mfa.enrollTOTP(
        issuer: "supabase.com", friendlyName: "Authenticator")

      #expect(
        enrollment
          == TOTPEnrollment(
            id: factorID, friendlyName: "Authenticator", qrCode: "<svg/>", secret: "SECRET",
            uri: "otpauth://totp/x"))

      _ = try await client.sut.mfa.enroll(
        params: MFATotpEnrollParams(issuer: "supabase.com", friendlyName: "Authenticator"))
      #expect(client.body(at: 0) == client.body(at: 1))
      #expect(client.body(at: 0)?["factor_type"] as? String == "totp")
    }

    @available(*, deprecated, message: "Compares with the deprecated v2 method.")
    @Test
    func enrollPhone() async throws {
      mock(
        "factors",
        data: Data(
          #"{"id": "0a1b2c3d-0000-4000-8000-000000000001", "type": "phone", "phone": "+15555550100"}"#
            .utf8))
      let client = signedInClient()

      let enrollment = try await client.sut.mfa.enrollPhone("+15555550100", friendlyName: "Phone")

      #expect(enrollment == PhoneEnrollment(id: factorID, phone: "+15555550100"))

      _ = try await client.sut.mfa.enroll(
        params: MFAPhoneEnrollParams(friendlyName: "Phone", phone: "+15555550100"))
      #expect(client.body(at: 0) == client.body(at: 1))
      #expect(client.body(at: 0)?["factor_type"] as? String == "phone")
    }

    @Test
    func challenge() async throws {
      mock(
        "\(factorPath)/challenge",
        data: Data(
          #"{"id": "0a1b2c3d-0000-4000-8000-000000000002", "type": "phone", "expires_at": 1700000000}"#
            .utf8))
      let client = signedInClient()

      let challenge = try await client.sut.mfa.challenge(factorID: factorID, channel: .whatsapp)

      #expect(
        challenge
          == MFAChallenge(
            id: challengeID, factorType: "phone",
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000)))
      #expect(client.lastBody == ["channel": "whatsapp"])

      _ = try await client.sut.mfa.challenge(factorID: factorID)
      #expect(client.lastRequest?.httpBody == nil)
    }

    @available(*, deprecated, message: "Compares with the deprecated v2 method.")
    @Test
    func verify() async throws {
      mock("\(factorPath)/verify", data: MockData.session)
      let client = signedInClient()

      let session = try await client.sut.mfa.verify(
        factorID: factorID, challengeID: challengeID, code: "123456")

      #expect(session.accessToken == Session(fromMockNamed: "session").accessToken)
      #expect(client.sut.currentSession == session)

      client.storeSession()
      try await client.sut.mfa.verify(
        params: MFAVerifyParams(
          factorId: "0a1b2c3d-0000-4000-8000-000000000001",
          challengeId: "0a1b2c3d-0000-4000-8000-000000000002", code: "123456"))
      #expect(client.body(at: 0) == client.body(at: 1))
      #expect(client.requests.value[0].url == client.requests.value[1].url)
    }

    @Test
    func challengeAndVerify() async throws {
      mock(
        "\(factorPath)/challenge",
        data: Data(
          #"{"id": "0a1b2c3d-0000-4000-8000-000000000002", "type": "totp", "expires_at": 1700000000}"#
            .utf8))
      mock("\(factorPath)/verify", data: MockData.session)
      let client = signedInClient()

      let session = try await client.sut.mfa.challengeAndVerify(factorID: factorID, code: "123456")

      #expect(session.accessToken == Session(fromMockNamed: "session").accessToken)
      #expect(
        client.lastBody == [
          "factor_id": "0a1b2c3d-0000-4000-8000-000000000001",
          "challenge_id": "0a1b2c3d-0000-4000-8000-000000000002",
          "code": "123456",
        ])
    }

    @Test
    func unenroll() async throws {
      mock(
        factorPath, .delete,
        data: Data(#"{"id": "0a1b2c3d-0000-4000-8000-000000000001"}"#.utf8))
      let client = signedInClient()

      let response = try await client.sut.mfa.unenroll(factorID: factorID)

      #expect(response.id == "0a1b2c3d-0000-4000-8000-000000000001")
      #expect(client.lastRequest?.httpMethod == "DELETE")
    }

    @Test
    func factorsSplitByStatus() async throws {
      let now = Date()
      let verified = Factor(
        id: "1", friendlyName: nil, factorType: "totp", status: .verified, createdAt: now,
        updatedAt: now)
      let unverified = Factor(
        id: "2", friendlyName: nil, factorType: "phone", status: .unverified, createdAt: now,
        updatedAt: now)
      var session = Session.validSession
      session.user.factors = [unverified, verified]
      let client = V3TestClient()
      client.storeSession(session)

      let factors = try await client.sut.mfa.factors()

      #expect(factors.verified == [verified])
      #expect(factors.unverified == [unverified])
      #expect(factors.all == [verified, unverified])
      #expect(factors == MFAFactors(verified: [verified], unverified: [unverified]))
    }

    @Test
    func assuranceLevel() async throws {
      // {"aal": "aal1", "amr": [{"method": "password", "timestamp": 1700000000}], "exp": 4102444800}
      let jwt =
        "eyJhbGciOiJIUzI1NiJ9.eyJhYWwiOiJhYWwxIiwiYW1yIjpbeyJtZXRob2QiOiJwYXNzd29yZCIsInRpbWVzdGFtcCI6MTcwMDAwMDAwMH1dLCJleHAiOjQxMDI0NDQ4MDB9.c2ln"
      let now = Date()
      var session = Session.validSession
      session.accessToken = jwt
      session.user.factors = [
        Factor(
          id: "1", friendlyName: nil, factorType: "totp", status: .verified, createdAt: now,
          updatedAt: now)
      ]
      let client = V3TestClient()
      client.storeSession(session)

      let info = try await client.sut.mfa.assuranceLevel()

      #expect(info.currentLevel == .aal1)
      #expect(info.nextLevel == .aal2)
      #expect(info.currentAuthenticationMethods.map(\.method) == ["password"])
      #expect(
        AssuranceLevelInfo(currentLevel: .aal1, currentAuthenticationMethods: []).nextLevel == nil)
    }

    @Test
    func assuranceLevelThrowsWithoutASession() async throws {
      let client = V3TestClient()

      await #expect(throws: AuthError.sessionMissing) {
        try await client.sut.mfa.assuranceLevel()
      }
    }
  }
}
