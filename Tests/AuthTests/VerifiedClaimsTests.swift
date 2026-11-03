import Foundation
import Testing

@testable import Auth
@testable import Helpers

@Suite
struct VerifiedClaimsTests {
  private func decode(payload: String) throws -> DecodedJWT {
    let header = Base64URL.encode(Data(#"{"alg":"ES256","kid":"kid-1","typ":"JWT"}"#.utf8))
    let body = Base64URL.encode(Data(payload.utf8))
    let signature = Base64URL.encode(Data("signature".utf8))
    return try #require(JWT.decode("\(header).\(body).\(signature)"))
  }

  @Test
  func snakeCaseClaimsLandInTypedFields() throws {
    let jwt = try decode(
      payload: #"""
        {"sub":"user-1","exp":1735689600,"session_id":"session-1",
        "app_metadata":{"provider":"email"},"user_metadata":{"name":"Ada"},
        "is_anonymous":false,"aal":"aal1"}
        """#
    )

    let claims = try VerifiedClaims(jwt)

    #expect(claims.subject == "user-1")
    #expect(claims.sessionID == "session-1")
    #expect(claims.appMetadata == ["provider": "email"])
    #expect(claims.userMetadata == ["name": "Ada"])
    #expect(claims.isAnonymous == false)
    #expect(claims.assuranceLevel == "aal1")
    #expect(claims.additionalClaims.isEmpty)
    #expect(claims.header.alg == "ES256")
    #expect(claims.header.kid == "kid-1")
    #expect(claims.signature == Data("signature".utf8))
  }

  @Test
  func audienceStringBecomesSingleElementArray() throws {
    let jwt = try decode(payload: #"{"sub":"user-1","exp":1735689600,"aud":"authenticated"}"#)

    let claims = try VerifiedClaims(jwt)

    #expect(claims.audience == ["authenticated"])
  }

  @Test
  func fractionalExpAndArrayAudience() throws {
    let jwt = try decode(payload: #"{"sub":"user-1","exp":1735689600.5,"aud":["a","b"]}"#)

    let claims = try VerifiedClaims(jwt)

    #expect(claims.expiresAt.timeIntervalSince1970 == 1_735_689_600.5)
    #expect(claims.audience == ["a", "b"])
  }

  @Test
  func amrObjectsAndStrings() throws {
    let jwt = try decode(
      payload: #"""
        {"sub":"user-1","exp":1735689600,"iat":1700000100,
        "amr":[{"method":"password","timestamp":1700000000},"otp"]}
        """#
    )

    let claims = try VerifiedClaims(jwt)

    #expect(claims.issuedAt?.timeIntervalSince1970 == 1_700_000_100)
    #expect(claims.amr.count == 2)
    #expect(claims.amr.first?.method == "password")
    #expect(claims.amr.first?.timestamp == 1_700_000_000)
    #expect(claims.amr.last?.method == "otp")
    #expect(claims.amr.last?.timestamp == 1_700_000_100)
  }

  @Test
  func customClaimsGoToAdditionalClaims() throws {
    let jwt = try decode(
      payload: #"{"sub":"user-1","exp":1735689600,"role":"authenticated","tenant":"acme"}"#
    )

    let claims = try VerifiedClaims(jwt)

    #expect(claims.role == "authenticated")
    #expect(claims.additionalClaims == ["tenant": "acme"])
    #expect(claims.appMetadata.isEmpty)
    #expect(claims.userMetadata.isEmpty)
  }

  @Test
  func missingExpThrows() throws {
    let jwt = try decode(payload: #"{"sub":"user-1"}"#)

    let error = #expect(throws: AuthError.self) { try VerifiedClaims(jwt) }
    #expect(error?.kind == .jwtVerificationFailed)
    #expect(error?.message == "JWT is missing the exp claim")
  }

  @Test
  func missingSubThrows() throws {
    let jwt = try decode(payload: #"{"exp":1735689600}"#)

    let error = #expect(throws: AuthError.self) { try VerifiedClaims(jwt) }
    #expect(error?.kind == .jwtVerificationFailed)
    #expect(error?.message == "JWT is missing the sub claim")
  }
}
