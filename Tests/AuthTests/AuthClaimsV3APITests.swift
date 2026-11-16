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
  struct AuthClaimsV3APITests {
    // HS256 tokens: the client cannot verify them on the device, so it asks the server.
    let fullToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI4NTlmNDAyZC1iM2RlLTQxMDUtYTFiOS05MzI4MzZkOTE5M2IiLCJpc3MiOiJodHRwczovL3Byb2plY3Quc3VwYWJhc2UuY28vYXV0aC92MSIsImF1ZCI6ImF1dGhlbnRpY2F0ZWQiLCJleHAiOjQxMDI0NDQ4MDAsImlhdCI6MTcwMDAwMDAwMCwicm9sZSI6ImF1dGhlbnRpY2F0ZWQiLCJlbWFpbCI6InVzZXJAZXhhbXBsZS5jb20iLCJhYWwiOiJhYWwxIiwiYW1yIjpbeyJtZXRob2QiOiJwYXNzd29yZCIsInRpbWVzdGFtcCI6MTcwMDAwMDAwMH0sIm90cCJdLCJzZXNzaW9uX2lkIjoic2Vzc2lvbi0xIiwiaXNfYW5vbnltb3VzIjpmYWxzZSwiYXBwX21ldGFkYXRhIjp7InByb3ZpZGVyIjoiZW1haWwifSwidXNlcl9tZXRhZGF0YSI6eyJmaXJzdE5hbWUiOiJBZGEifSwianRpIjoidG9rZW4tMSIsImN1c3RvbV9jbGFpbSI6eyJwbGFuIjoicHJvIn19.c2lnbmF0dXJl"
    /// `{"sub": "user", "aud": ["a", "b"], "exp": 1000}`
    let expiredToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyIiwiYXVkIjpbImEiLCJiIl0sImV4cCI6MTAwMH0.c2lnbmF0dXJl"
    /// `{"aud": "authenticated", "exp": 4102444800}`
    let tokenWithoutSubject =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjo0MTAyNDQ0ODAwfQ.c2lnbmF0dXJl"

    init() {
      Mocker.removeAll()
    }

    @Test
    func claimsOfAGivenToken() async throws {
      mock("user", .get, data: MockData.user)
      let client = V3TestClient()

      let claims = try await client.sut.claims(jwt: fullToken)

      #expect(claims.subject == "859f402d-b3de-4105-a1b9-932836d9193b")
      #expect(claims.issuer == "https://project.supabase.co/auth/v1")
      #expect(claims.audience == ["authenticated"])
      #expect(claims.expiresAt == Date(timeIntervalSince1970: 4_102_444_800))
      #expect(claims.issuedAt == Date(timeIntervalSince1970: 1_700_000_000))
      #expect(claims.notBefore == nil)
      #expect(claims.role == "authenticated")
      #expect(claims.email == "user@example.com")
      #expect(claims.phone == nil)
      #expect(claims.assuranceLevel == .aal1)
      #expect(claims.amr.map(\.method) == ["password", "otp"])
      #expect(claims.amr.map(\.timestamp) == [1_700_000_000, 1_700_000_000])
      #expect(claims.sessionID == "session-1")
      #expect(claims.isAnonymous == false)
      #expect(claims.appMetadata == ["provider": "email"])
      #expect(claims.userMetadata == ["firstName": "Ada"])
      #expect(claims.additionalClaims == ["jti": "token-1", "custom_claim": ["plan": "pro"]])
      #expect(claims.header == JWTHeader(alg: "HS256", typ: "JWT"))
      #expect(claims.signature == Data("signature".utf8))
      #expect(
        client.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer \(fullToken)")
    }

    @Test
    func claimsOfTheSession() async throws {
      mock("user", .get, data: MockData.user)
      let client = V3TestClient()

      await #expect(throws: AuthError.sessionMissing) {
        try await client.sut.claims()
      }

      var session = Session.validSession
      session.accessToken = fullToken
      client.storeSession(session)

      let claims = try await client.sut.claims()
      #expect(claims.subject == "859f402d-b3de-4105-a1b9-932836d9193b")
    }

    @Test
    func expiredTokenNeedsAllowsExpired() async throws {
      mock("user", .get, data: MockData.user)
      let client = V3TestClient()

      await #expect(throws: AuthError.jwtVerificationFailed(message: "JWT has expired")) {
        try await client.sut.claims(jwt: expiredToken)
      }

      let claims = try await client.sut.claims(
        jwt: expiredToken, options: ClaimsOptions(allowsExpired: true))
      #expect(claims.audience == ["a", "b"])
      #expect(claims.expiresAt == Date(timeIntervalSince1970: 1000))
      #expect(claims.amr.isEmpty)
      #expect(claims.appMetadata.isEmpty)
    }

    @Test
    func tokenWithoutSubjectFails() async throws {
      mock("user", .get, data: MockData.user)
      let client = V3TestClient()

      await #expect(
        throws: AuthError.jwtVerificationFailed(message: "JWT is missing the sub claim")
      ) {
        try await client.sut.claims(jwt: tokenWithoutSubject)
      }
    }

    @Test
    func claimsOptionsDefaults() {
      #expect(ClaimsOptions() == ClaimsOptions(allowsExpired: false, jwks: nil))
      #expect(ClaimsOptions(allowsExpired: true).allowsExpired)
    }

    @available(*, deprecated, message: "Covers the deprecated v2 method.")
    @Test
    func getClaimsKeepsItsResult() async throws {
      mock("user", .get, data: MockData.user)
      let client = V3TestClient()

      let response = try await client.sut.getClaims(jwt: fullToken)

      #expect(response.claims.sub == "859f402d-b3de-4105-a1b9-932836d9193b")
      #expect(response.claims.aud == .string("authenticated"))
      #expect(response.header.alg == "HS256")
    }
  }
}
