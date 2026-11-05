import ConcurrencyExtras
import CustomDump
import Foundation
import Helpers
import InlineSnapshotTesting
import Mocker
import TestHelpers
import Testing

@_spi(Experimental) @testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

#if canImport(AuthenticationServices)
  import AuthenticationServices
#endif

extension AuthClientTests {
  @Test
  func removeSessionAndSignoutIfRefreshTokenNotFoundErrorReturned() async throws {
    let sut = makeSUT()

    Mock(
      url: clientURL.appendingPathComponent("token").appendingQueryItems([
        URLQueryItem(name: "grant_type", value: "refresh_token")
      ]),
      statusCode: 403,
      data: [
        .post: Data(
          """
          {
            "error_code": "refresh_token_not_found",
            "message": "Invalid Refresh Token: Refresh Token Not Found"
          }
          """.utf8
        )
      ]
    )
    .register()

    try await sut.seedSession(.expired)

    let expectedEvents = [AuthEvent.initialSession, .signedOut]

    try await assertAuthStateChanges(
      sut: sut,
      action: {
        do {
          _ = try await sut.session()
          Issue.record("Expected failure")
        } catch {
          // `.initialSession` starts a background refresh of the expired session. If it
          // finishes first, nothing is stored when `session` runs.
          let kind = (error as? AuthError)?.kind
          #expect(kind == .sessionInvalidated || kind == .sessionMissing)
        }
      },
      expectedEvents: expectedEvents
    )

    #expect(sut.dependencies.sessionStore.currentStatus == .signedOut(.sessionExpired))
  }

  @Test
  func refreshToken() async throws {
    let sut = makeSUT()

    Mock(
      url: clientURL.appendingPathComponent("token").appendingQueryItems([
        URLQueryItem(name: "grant_type", value: "refresh_token")
      ]),
      statusCode: 200,
      data: [.post: try AuthClient.Configuration.jsonEncoder.encode(Session.valid)]
    )
    .register()

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
    let jwksRequests = try mockJWKS(signer.jwk)

    let sut = makeSUT()

    let result = try await sut.claims(jwt: jwt)

    #expect(result.subject == "1234567890")
    #expect(result.header.kid == "es256-test-kid")
    #expect(jwksRequests.value == 1)
  }

  @Test
  func claimsCachesJWKSAcrossCalls() async throws {
    let signer = ES256TestSigner()
    let jwt = try signer.sign(
      header: #"{"alg":"ES256","kid":"es256-test-kid","typ":"JWT"}"#,
      payload: #"{"sub":"1234567890","exp":9999999999}"#
    )
    let jwksRequests = try mockJWKS(signer.jwk)

    let sut = makeSUT()

    _ = try await sut.claims(jwt: jwt)
    _ = try await sut.claims(jwt: jwt)

    #expect(jwksRequests.value == 1)
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
    let firstRequests = try mockJWKS(signer.jwk)
    let secondRequests = try mockJWKS(signer.jwk, url: otherURL)

    let first = makeSUT(storageKey: storageKey)
    let second = makeSUT(url: otherURL, storageKey: storageKey)

    _ = try await first.claims(jwt: jwt)
    _ = try await second.claims(jwt: jwt)

    #expect(firstRequests.value == 1)
    #expect(secondRequests.value == 1)
  }

  @Test
  func claimsFallsBackWhenKidUnknown() async throws {
    let signer = ES256TestSigner()
    let jwt = try signer.sign(
      header: #"{"alg":"ES256","kid":"rotated-kid","typ":"JWT"}"#,
      payload: #"{"sub":"1234567890","exp":9999999999}"#
    )
    let jwksRequests = try mockJWKS(signer.jwk)
    let userRequests = try mockUser()

    let sut = makeSUT()

    let result = try await sut.claims(jwt: jwt)

    #expect(result.subject == "1234567890")
    #expect(jwksRequests.value == 1)
    #expect(userRequests.value == 1)
  }

  @Test
  func claimsRejectsMissingExp() async throws {
    let signer = ES256TestSigner()
    let jwt = try signer.sign(
      header: #"{"alg":"ES256","kid":"es256-test-kid","typ":"JWT"}"#,
      payload: #"{"sub":"1234567890"}"#
    )
    let jwksRequests = try mockJWKS(signer.jwk)
    let userRequests = try mockUser()

    let sut = makeSUT()

    let error = await #expect(throws: AuthError.self) {
      _ = try await sut.claims(jwt: jwt, options: ClaimsOptions(allowsExpired: true))
    }
    #expect(error?.kind == .jwtVerificationFailed)
    #expect(jwksRequests.value == 0)
    #expect(userRequests.value == 0)
  }

  @Test
  func claimsRejectsExpiredUnlessAllowed() async throws {
    let expiredJWT =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6MTUxNjIzOTAyMiwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.aN0HLYHkp7nKZp4xWvBaDqSrCFBxk2tq0KZc4BXGqYs"
    let userRequests = try mockUser()

    let sut = makeSUT()

    let error = await #expect(throws: AuthError.self) {
      _ = try await sut.claims(jwt: expiredJWT)
    }
    #expect(error?.kind == .jwtVerificationFailed)
    #expect(error?.message == "JWT has expired")
    #expect(userRequests.value == 0)

    let result = try await sut.claims(
      jwt: expiredJWT,
      options: ClaimsOptions(allowsExpired: true)
    )

    #expect(result.subject == "1234567890")
    #expect(result.expiresAt.timeIntervalSince1970 == 1_516_239_022)
    #expect(userRequests.value == 1)
  }

  @Test
  func claimsPropagatesRefreshError() async throws {
    Mock(
      url: clientURL.appendingPathComponent("token").appendingQueryItems([
        URLQueryItem(name: "grant_type", value: "refresh_token")
      ]),
      statusCode: 400,
      data: [
        .post: Data(
          """
          {
            "error_code": "refresh_token_not_found",
            "message": "Invalid Refresh Token: Refresh Token Not Found"
          }
          """.utf8
        )
      ]
    )
    .register()

    let sut = makeSUT()
    try await sut.seedSession(.expired)

    let refreshError = await #expect(throws: AuthError.self) {
      _ = try await sut.claims()
    }
    #expect(refreshError?.kind == .sessionInvalidated)
    #expect(refreshError?.errorCode == .refreshTokenNotFound)

    let signedOutError = await #expect(throws: AuthError.self) {
      _ = try await sut.claims()
    }
    #expect(signedOutError?.kind == .sessionMissing)
  }

  @Test
  func claimsFallsBackToUserForHS256() async throws {
    let jwt =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.4Adcj0vZKqXRB_mPpDVkWvB3xw7yHYjpzGJLKFQjKEc"
    let userRequests = try mockUser()

    let sut = makeSUT()

    let result = try await sut.claims(jwt: jwt)

    #expect(userRequests.value == 1)
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

    let user = User(fromMockNamed: "user")

    Mock(
      url: clientURL.appendingPathComponent("user"),
      ignoreQuery: true,
      contentType: .json,
      statusCode: 200,
      data: [.get: try! AuthClient.Configuration.jsonEncoder.encode(user)]
    ).register()

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

    Mock(
      url: clientURL.appendingPathComponent("user"),
      ignoreQuery: true,
      contentType: .json,
      statusCode: 401,
      data: [.get: Data()]
    ).register()

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

    Mock(
      url: clientURL.appendingPathComponent("user"),
      ignoreQuery: true,
      contentType: .json,
      statusCode: 401,
      data: [.get: Data()]
    ).register()

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

    Mock(
      url: clientURL.appendingPathComponent("user"),
      ignoreQuery: true,
      contentType: .json,
      statusCode: 401,
      data: [.get: Data()]
    ).register()

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

    let user = User(fromMockNamed: "user")

    Mock(
      url: clientURL.appendingPathComponent("user"),
      ignoreQuery: true,
      contentType: .json,
      statusCode: 200,
      data: [.get: try! AuthClient.Configuration.jsonEncoder.encode(user)]
    ).register()

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

    let user = User(fromMockNamed: "user")

    Mock(
      url: clientURL.appendingPathComponent("user"),
      ignoreQuery: true,
      contentType: .json,
      statusCode: 200,
      data: [.get: try! AuthClient.Configuration.jsonEncoder.encode(user)]
    ).register()

    let sut = makeSUT()

    let result = try await sut.claims(jwt: jwt)

    #expect(result.subject == "1234567890")
    #expect(result.role == "authenticated")
  }

  @Test
  func claims_withNoKidInHeader_shouldFallbackToServerVerification() async throws {
    let jwt =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI5ODc2NTQzMjEiLCJpc3MiOiJodHRwOi8vbG9jYWxob3N0OjU0MzIxL2F1dGgvdjEiLCJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjo5OTk5OTk5OTk5LCJpYXQiOjE1MTYyMzkwMjIsInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.YT0NvH-jYKCiN-wrAVcMmTIxZkQ3OtqTVFjJAqGcRuw"

    let user = User(fromMockNamed: "user")

    Mock(
      url: clientURL.appendingPathComponent("user"),
      ignoreQuery: true,
      contentType: .json,
      statusCode: 200,
      data: [.get: try! AuthClient.Configuration.jsonEncoder.encode(user)]
    ).register()

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

    Mock(
      url: clientURL.appendingPathComponent("user"),
      ignoreQuery: true,
      contentType: .json,
      statusCode: 401,
      data: [
        .get: try! AuthClient.Configuration.jsonEncoder.encode([
          "error": "invalid_token",
          "error_description": "Invalid JWT",
        ])
      ]
    ).register()

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

    let user = User(fromMockNamed: "user")

    Mock(
      url: clientURL.appendingPathComponent("user"),
      ignoreQuery: true,
      contentType: .json,
      statusCode: 200,
      data: [.get: try! AuthClient.Configuration.jsonEncoder.encode(user)]
    ).register()

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

    let user = User(fromMockNamed: "user")

    Mock(
      url: clientURL.appendingPathComponent("user"),
      ignoreQuery: true,
      contentType: .json,
      statusCode: 200,
      data: [.get: try! AuthClient.Configuration.jsonEncoder.encode(user)]
    ).register()

    let sut = makeSUT()

    let result = try await sut.claims(jwt: jwt)

    #expect(result.subject == "1234567890")
    #expect(result.audience == ["authenticated", "service-role"])
  }

  @Test
  func transportFailureIsWrapped() async {
    Mock(
      url: clientURL.appendingPathComponent("token"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: Data()],
      requestError: URLError(.notConnectedToInternet)
    )
    .register()

    let sut = makeSUT()

    do {
      try await sut.signIn(email: "a@b.c", password: "secret")
      Issue.record("Expected failure")
    } catch let error as AuthError {
      #expect(error.kind == .transport)
      #expect(error.errorCode == .unknown)
      #expect((error.underlyingError as? URLError)?.code == .notConnectedToInternet)
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test
  func unexpectedResponseBodyIsReported() async {
    Mock(
      url: clientURL.appendingPathComponent("token"),
      ignoreQuery: true,
      statusCode: 502,
      data: [.post: Data("<html>bad gateway</html>".utf8)]
    )
    .register()

    let sut = makeSUT()

    do {
      try await sut.signIn(email: "a@b.c", password: "secret")
      Issue.record("Expected failure")
    } catch let error as AuthError {
      #expect(error.kind == .server)
      #expect(error.errorCode == .unexpectedFailure)
      #expect(error.response?.statusCode == 502)
      #expect(error.response?.body == Data("<html>bad gateway</html>".utf8))
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test
  func undecodableSuccessBodyIsWrapped() async {
    Mock(
      url: clientURL.appendingPathComponent("token"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: Data("not json".utf8)]
    )
    .register()

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
