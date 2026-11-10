import Foundation
import Helpers
import TestHelpers
import Testing

@_spi(Experimental) @testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension AuthClientTests {
  @Test
  func removeSessionAndSignoutIfRefreshTokenNotFoundErrorReturned() async throws {
    let sut = makeSUT()

    transport.stub(
      .post, "token", query: ["grant_type": "refresh_token"], status: .forbidden,
      data: Data(
        """
        {
          "error_code": "refresh_token_not_found",
          "message": "Invalid Refresh Token: Refresh Token Not Found"
        }
        """.utf8
      ))

    try await sut.seedSession(.expired)

    let expectedEvents = [AuthEvent.initialSession, .signedOut]

    try await assertAuthStateChanges(
      sut: sut,
      action: {
        do {
          _ = try await sut.session()
          Issue.record("Expected failure")
        } catch {
          #expect((error as? AuthError)?.kind == .sessionInvalidated)
        }
      },
      expectedEvents: expectedEvents
    )

    #expect(sut.dependencies.sessionStore.currentStatus == .signedOut(.sessionExpired))
  }

  @Test
  func refreshToken() async throws {
    let sut = makeSUT()

    transport.stub(
      .post, "token", query: ["grant_type": "refresh_token"],
      data: try AuthClient.Configuration.jsonEncoder.encode(Session.valid))

    try await sut.seedSession(.expired)

    let expectedEvents = [AuthEvent.initialSession, .tokenRefreshed]

    try await assertAuthStateChanges(
      sut: sut,
      action: {
        _ = try await sut.session()
      },
      expectedEvents: expectedEvents
    )
  }

  @Test
  func claimsVerifiesLocallyWithoutUserRequest() async throws {
    let signer = ES256TestSigner()
    let jwt = try signer.sign(
      header: #"{"alg":"ES256","kid":"es256-test-kid","typ":"JWT"}"#,
      payload: #"{"sub":"1234567890","exp":9999999999,"role":"authenticated"}"#
    )
    try transport.stubJWKS(signer.jwk)

    let sut = makeSUT()

    let result = try await sut.claims(jwt: jwt)

    #expect(result.subject == "1234567890")
    #expect(result.header.kid == "es256-test-kid")
    #expect(transport.jwksRequestCount() == 1)
  }

  @Test
  func claimsCachesJWKSAcrossCalls() async throws {
    let signer = ES256TestSigner()
    let jwt = try signer.sign(
      header: #"{"alg":"ES256","kid":"es256-test-kid","typ":"JWT"}"#,
      payload: #"{"sub":"1234567890","exp":9999999999}"#
    )
    try transport.stubJWKS(signer.jwk)

    let sut = makeSUT()

    _ = try await sut.claims(jwt: jwt)
    _ = try await sut.claims(jwt: jwt)

    #expect(transport.jwksRequestCount() == 1)
  }

  @Test
  func twoClientsDoNotShareJWKS() async throws {
    let otherURL = URL(string: "http://other-project.localhost/auth/v1")!
    let storageKey = uniqueStorageKey()
    let signer = ES256TestSigner()
    let jwt = try signer.sign(
      header: #"{"alg":"ES256","kid":"es256-test-kid","typ":"JWT"}"#,
      payload: #"{"sub":"1234567890","exp":9999999999}"#
    )
    try transport.stubJWKS(signer.jwk)
    try transport.stubJWKS(signer.jwk, baseURL: otherURL)

    let first = makeSUT(storageKey: storageKey)
    let second = makeSUT(url: otherURL, storageKey: storageKey)

    _ = try await first.claims(jwt: jwt)
    _ = try await second.claims(jwt: jwt)

    #expect(transport.jwksRequestCount(host: clientURL.host) == 1)
    #expect(transport.jwksRequestCount(host: otherURL.host) == 1)
  }

  @Test
  func claimsFallsBackWhenKidUnknown() async throws {
    let signer = ES256TestSigner()
    let jwt = try signer.sign(
      header: #"{"alg":"ES256","kid":"rotated-kid","typ":"JWT"}"#,
      payload: #"{"sub":"1234567890","exp":9999999999}"#
    )
    try transport.stubJWKS(signer.jwk)
    try transport.stubUser()

    let sut = makeSUT()

    let result = try await sut.claims(jwt: jwt)

    #expect(result.subject == "1234567890")
    #expect(transport.jwksRequestCount() == 1)
    #expect(transport.userRequestCount == 1)
  }

  @Test
  func claimsRejectsMissingExp() async throws {
    let signer = ES256TestSigner()
    let jwt = try signer.sign(
      header: #"{"alg":"ES256","kid":"es256-test-kid","typ":"JWT"}"#,
      payload: #"{"sub":"1234567890"}"#
    )
    try transport.stubJWKS(signer.jwk)
    try transport.stubUser()

    let sut = makeSUT()

    let error = await #expect(throws: AuthError.self) {
      _ = try await sut.claims(jwt: jwt, options: ClaimsOptions(allowsExpired: true))
    }
    #expect(error?.kind == .jwtVerificationFailed)
    #expect(transport.jwksRequestCount() == 0)
    #expect(transport.userRequestCount == 0)
  }

  @Test
  func claimsRejectsExpiredUnlessAllowed() async throws {
    let expiredJWT =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6MTUxNjIzOTAyMiwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.aN0HLYHkp7nKZp4xWvBaDqSrCFBxk2tq0KZc4BXGqYs"
    try transport.stubUser()

    let sut = makeSUT()

    let error = await #expect(throws: AuthError.self) {
      _ = try await sut.claims(jwt: expiredJWT)
    }
    #expect(error?.kind == .jwtVerificationFailed)
    #expect(error?.message == "JWT has expired")
    #expect(transport.userRequestCount == 0)

    let result = try await sut.claims(
      jwt: expiredJWT,
      options: ClaimsOptions(allowsExpired: true)
    )

    #expect(result.subject == "1234567890")
    #expect(result.expiresAt.timeIntervalSince1970 == 1_516_239_022)
    #expect(transport.userRequestCount == 1)
  }

  @Test
  func claimsPropagatesRefreshError() async throws {
    transport.stub(
      .post, "token", query: ["grant_type": "refresh_token"], status: .badRequest,
      data: Data(
        """
        {
          "error_code": "refresh_token_not_found",
          "message": "Invalid Refresh Token: Refresh Token Not Found"
        }
        """.utf8
      ))

    let sut = makeSUT()
    try await sut.seedSession(.expired)

    let refreshError = await #expect(throws: AuthError.self) {
      _ = try await sut.claims()
    }
    #expect(refreshError?.kind == .sessionInvalidated)
    #expect(refreshError?.code == .refreshTokenNotFound)

    let signedOutError = await #expect(throws: AuthError.self) {
      _ = try await sut.claims()
    }
    #expect(signedOutError?.kind == .sessionMissing)
  }

  @Test
  func claimsFallsBackToUserForHS256() async throws {
    let jwt =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.4Adcj0vZKqXRB_mPpDVkWvB3xw7yHYjpzGJLKFQjKEc"
    try transport.stubUser()

    let sut = makeSUT()

    let result = try await sut.claims(jwt: jwt)

    #expect(transport.userRequestCount == 1)
    #expect(result.subject == "1234567890")
    #expect(result.issuer == "http://localhost:54321/auth/v1")
    #expect(result.audience == ["authenticated"])
    #expect(result.role == "authenticated")
    #expect(result.header.alg == "HS256")
    #expect(result.header.kid == nil)
  }

  @Test
  func claims_withoutJWT_shouldUseSessionAccessToken() async throws {
    let jwt =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.4Adcj0vZKqXRB_mPpDVkWvB3xw7yHYjpzGJLKFQjKEc"

    var session = Session.valid
    session.accessToken = jwt

    try transport.stubUser()

    let sut = makeSUT()
    try await sut.seedSession(session)

    let result = try await sut.claims()

    #expect(result.subject == "1234567890")
    #expect(result.role == "authenticated")
  }

  @Test
  func claims_withES256JWTAndJWKS_shouldVerifyLocally() async throws {
    let signer = ES256TestSigner()
    let jwt = try signer.sign(
      header: #"{"alg":"ES256","kid":"es256-test-kid","typ":"JWT"}"#,
      payload:
        #"{"sub":"1234567890","iss":"http://localhost:54321/auth/v1","aud":"authenticated","exp":9999999999,"iat":1516239022,"role":"authenticated"}"#
    )

    transport.stub(.get, "user", status: .unauthorized)

    let sut = makeSUT()

    let result = try await sut.claims(
      jwt: jwt,
      options: ClaimsOptions(jwks: JWKS(keys: [signer.jwk]))
    )

    #expect(result.subject == "1234567890")
    #expect(result.role == "authenticated")
    #expect(result.header.alg == "ES256")
    #expect(result.header.kid == "es256-test-kid")
  }

  @Test
  func claims_withJWKMissingAlg_shouldVerifyLocally() async throws {
    let signer = ES256TestSigner()
    let jwt = try signer.sign(
      header: #"{"alg":"ES256","kid":"es256-test-kid","typ":"JWT"}"#,
      payload:
        #"{"sub":"1234567890","iss":"http://localhost:54321/auth/v1","aud":"authenticated","exp":9999999999,"iat":1516239022,"role":"authenticated"}"#
    )
    let key = signer.jwk
    let keyWithoutAlg = JWK(
      kty: key.kty,
      keyOps: key.keyOps,
      alg: nil,
      kid: key.kid,
      n: key.n,
      e: key.e,
      crv: key.crv,
      x: key.x,
      y: key.y,
      k: key.k
    )

    transport.stub(.get, "user", status: .unauthorized)

    let sut = makeSUT()

    let result = try await sut.claims(
      jwt: jwt,
      options: ClaimsOptions(jwks: JWKS(keys: [keyWithoutAlg]))
    )

    #expect(result.subject == "1234567890")
    #expect(result.role == "authenticated")
    #expect(result.header.alg == "ES256")
  }

  @Test
  func claims_withJWKMissingAlgAndMismatchedHeaderAlg_shouldVerifyWithJWKAlgorithm()
    async throws
  {
    let signer = ES256TestSigner()
    let jwt = try signer.sign(
      header: #"{"alg":"RS256","kid":"es256-test-kid","typ":"JWT"}"#,
      payload: #"{"sub":"1234567890","exp":9999999999,"role":"authenticated"}"#
    )
    let key = signer.jwk
    let keyWithoutAlg = JWK(
      kty: key.kty,
      keyOps: key.keyOps,
      alg: nil,
      kid: key.kid,
      n: key.n,
      e: key.e,
      crv: key.crv,
      x: key.x,
      y: key.y,
      k: key.k
    )

    transport.stub(.get, "user", status: .unauthorized)

    let sut = makeSUT()

    let result = try await sut.claims(
      jwt: jwt,
      options: ClaimsOptions(jwks: JWKS(keys: [keyWithoutAlg]))
    )

    #expect(result.subject == "1234567890")
    #expect(result.header.alg == "RS256")
  }

  @Test
  func claims_withTamperedES256JWT_shouldThrowWithoutFallback() async throws {
    let signer = ES256TestSigner()
    let jwt = try signer.sign(
      header: #"{"alg":"ES256","kid":"es256-test-kid","typ":"JWT"}"#,
      payload: #"{"sub":"1234567890","exp":9999999999,"role":"authenticated"}"#
    )
    let parts = jwt.split(separator: ".")
    let tamperedPayload = Base64URL.encode(
      Data(#"{"sub":"1234567890","exp":9999999999,"role":"service_role"}"#.utf8)
    )
    let tamperedJWT = "\(parts[0]).\(tamperedPayload).\(parts[2])"

    try transport.stubUser()

    let sut = makeSUT()

    let error = await #expect(throws: AuthError.self) {
      _ = try await sut.claims(
        jwt: tamperedJWT,
        options: ClaimsOptions(jwks: JWKS(keys: [signer.jwk]))
      )
    }
    #expect(error?.kind == .jwtVerificationFailed)
    #expect(error?.message == "Invalid JWT signature")
  }

  @Test
  func claims_withES256JWT_shouldFallbackToServerVerification() async throws {
    let jwt =
      "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.dummysignature"

    try transport.stubUser()

    let sut = makeSUT()

    let result = try await sut.claims(jwt: jwt)

    #expect(result.subject == "1234567890")
    #expect(result.role == "authenticated")
  }

  @Test
  func claims_withNoKidInHeader_shouldFallbackToServerVerification() async throws {
    let jwt =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI5ODc2NTQzMjEiLCJpc3MiOiJodHRwOi8vbG9jYWxob3N0OjU0MzIxL2F1dGgvdjEiLCJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjo5OTk5OTk5OTk5LCJpYXQiOjE1MTYyMzkwMjIsInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.YT0NvH-jYKCiN-wrAVcMmTIxZkQ3OtqTVFjJAqGcRuw"

    try transport.stubUser()

    let sut = makeSUT()

    let result = try await sut.claims(jwt: jwt)

    #expect(result.subject == "987654321")
    #expect(result.role == "authenticated")
  }

  @Test
  func claims_withInvalidJWTStructure_shouldThrowJWTVerificationFailed() async throws {
    let invalidJWT = "invalid.jwt.token"

    let sut = makeSUT()

    do {
      _ = try await sut.claims(jwt: invalidJWT)
      Issue.record("Expected jwtVerificationFailed error")
    } catch let error as AuthError {
      #expect(error.kind == .jwtVerificationFailed)
      #expect(error.message == "Invalid JWT structure")
    } catch {
      Issue.record("Expected AuthError, got \(error)")
    }
  }

  @Test
  func claims_whenServerRejectsJWT_shouldThrowError() async throws {
    let jwt =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.4Adcj0vZKqXRB_mPpDVkWvB3xw7yHYjpzGJLKFQjKEc"

    transport.stub(
      .get, "user", status: .unauthorized,
      data: try AuthClient.Configuration.jsonEncoder.encode([
        "error": "invalid_token",
        "error_description": "Invalid JWT",
      ]))

    let sut = makeSUT()

    do {
      _ = try await sut.claims(jwt: jwt)
      Issue.record("Expected error from server")
    } catch {
    }
  }

  @Test
  func claims_withComplexClaims_shouldDecodeAllFields() async throws {
    let jwt =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJuYmYiOjE1MTYyMzkwMjIsImp0aSI6InRlc3QtanRpIiwicm9sZSI6ImF1dGhlbnRpY2F0ZWQiLCJlbWFpbCI6InRlc3RAZXhhbXBsZS5jb20iLCJwaG9uZSI6IisxMjM0NTY3ODkwIn0.dBYm1Y-TfRjPsxw_gXqHB5zGHSH9hXS0OeFN_wL8HbA"

    try transport.stubUser()

    let sut = makeSUT()

    let result = try await sut.claims(jwt: jwt)

    #expect(result.subject == "1234567890")
    #expect(result.issuer == "http://localhost:54321/auth/v1")
    #expect(result.audience == ["authenticated"])
    #expect(result.expiresAt.timeIntervalSince1970 == 9_999_999_999)
    #expect(result.issuedAt?.timeIntervalSince1970 == 1_516_239_022)
    #expect(result.notBefore?.timeIntervalSince1970 == 1_516_239_022)
    #expect(result.additionalClaims["nbf"] == nil)
    #expect(result.additionalClaims["jti"] == "test-jti")
    #expect(result.role == "authenticated")
    #expect(result.email == "test@example.com")
    #expect(result.phone == "+1234567890")
  }

  @Test
  func claims_withArrayAudience_shouldDecodeCorrectly() async throws {
    let jwt =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjpbImF1dGhlbnRpY2F0ZWQiLCJzZXJ2aWNlLXJvbGUiXSwiZXhwIjo5OTk5OTk5OTk5LCJpYXQiOjE1MTYyMzkwMjIsInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.Jz-lHQoR2VsQ_vX8wKyN7mPxT4aU9cF1bYsHqGdWlIk"

    try transport.stubUser()

    let sut = makeSUT()

    let result = try await sut.claims(jwt: jwt)

    #expect(result.subject == "1234567890")
    #expect(result.audience == ["authenticated", "service-role"])
  }

  @Test
  func transportFailureIsWrapped() async {
    transport.stub(.post, "token") { _, _ in throw URLError(.notConnectedToInternet) }

    let sut = makeSUT()

    do {
      try await sut.signIn(email: "a@b.c", password: "secret")
      Issue.record("Expected failure")
    } catch let error as AuthError {
      #expect(error.kind == .transport)
      #expect(error.code == nil)
      #expect((error.underlyingError as? URLError)?.code == .notConnectedToInternet)
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test
  func unexpectedResponseBodyIsReported() async {
    transport.stub(
      .post, "token", status: .badGateway, data: Data("<html>bad gateway</html>".utf8))

    let sut = makeSUT()

    do {
      try await sut.signIn(email: "a@b.c", password: "secret")
      Issue.record("Expected failure")
    } catch let error as AuthError {
      #expect(error.kind == .server)
      #expect(error.code == nil)
      #expect(error.response?.status == 502)
      #expect(error.response?.body == Data("<html>bad gateway</html>".utf8))
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test
  func undecodableSuccessBodyIsWrapped() async {
    transport.stub(.post, "token", data: Data("not json".utf8))

    let sut = makeSUT()

    do {
      try await sut.signIn(email: "a@b.c", password: "secret")
      Issue.record("Expected failure")
    } catch let error as AuthError {
      #expect(error.kind == .decoding)
      #expect(error.underlyingError is DecodingError)
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }
}
