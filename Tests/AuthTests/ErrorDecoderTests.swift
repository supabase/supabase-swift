//
//  ErrorDecoderTests.swift
//  AuthTests
//
//  Created by Guilherme Souza on 26/10/26.
//

import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@testable import Auth

@Suite
struct ErrorDecoderTests {
  static let signInRequest = HTTPTypes.HTTPRequest(
    method: .post, url: URL(string: "http://localhost/auth/v1/token?grant_type=password")!)
  static let refreshRequest = HTTPTypes.HTTPRequest(
    method: .post, url: URL(string: "http://localhost/auth/v1/token?grant_type=refresh_token")!)
  static let idTokenRequest = HTTPTypes.HTTPRequest(
    method: .post, url: URL(string: "http://localhost/auth/v1/token?grant_type=id_token")!)

  private static func decode(
    status: Int,
    body: String,
    contentType: String? = "application/json",
    request: HTTPTypes.HTTPRequest = signInRequest
  ) throws -> AuthError {
    var headers = HTTPFields()
    headers[.contentType] = contentType
    return try #require(
      ErrorDecoder.error(
        response: HTTPTypes.HTTPResponse(status: .init(code: status), headerFields: headers),
        data: Data(body.utf8),
        request: request
      ))
  }

  // MARK: Legacy shape

  @Test
  func legacyInvalidCredentials() throws {
    let body = #"{"code":400,"error_code":"invalid_credentials","msg":"Invalid login credentials"}"#
    let error = try Self.decode(status: 400, body: body)

    #expect(error.kind == .server)
    #expect(error.errorCode == .invalidCredentials)
    #expect(error.message == "Invalid login credentials")
    #expect(error.oauthError == nil)
    #expect(error.response?.statusCode == 400)
    #expect(error.response?.body == Data(body.utf8))
  }

  @Test
  func legacyWeakPasswordCarriesReasons() throws {
    let error = try Self.decode(
      status: 422,
      body: #"""
        {"code":422,"error_code":"weak_password","msg":"Password is too weak",
         "weak_password":{"reasons":["length","characters","pwned"]}}
        """#)

    #expect(error.kind == .server)
    #expect(error.errorCode == .weakPassword)
    #expect(error.weakPasswordReasons == ["length", "characters", "pwned"])
  }

  @Test
  func legacySessionNotFoundInvalidatesSession() throws {
    let error = try Self.decode(
      status: 403,
      body: #"{"code":403,"error_code":"session_not_found","msg":"Session not found"}"#)

    #expect(error.kind == .sessionInvalidated)
    #expect(error.errorCode == .sessionNotFound)
    #expect(error.message == "Session not found")
  }

  @Test
  func legacyBodyWithoutErrorCodeKeepsMessage() throws {
    let error = try Self.decode(
      status: 500, body: #"{"code":500,"msg":"Error sending confirmation email"}"#)

    #expect(error.kind == .server)
    #expect(error.errorCode == .unknown)
    #expect(error.message == "Error sending confirmation email")
  }

  // MARK: 2024-01-01 shape

  @Test
  func versionedInvalidCredentials() throws {
    let error = try Self.decode(
      status: 400, body: #"{"code":"invalid_credentials","message":"Invalid login credentials"}"#)

    #expect(error.kind == .server)
    #expect(error.errorCode == .invalidCredentials)
    #expect(error.message == "Invalid login credentials")
    #expect(error.oauthError == nil)
  }

  @Test
  func versionedWeakPasswordCarriesReasons() throws {
    let error = try Self.decode(
      status: 422,
      body: #"""
        {"code":"weak_password","message":"Password is too weak",
         "weak_password":{"reasons":["pwned"]}}
        """#)

    #expect(error.errorCode == .weakPassword)
    #expect(error.weakPasswordReasons == ["pwned"])
  }

  @Test
  func versionedRefreshTokenNotFoundInvalidatesSession() throws {
    let error = try Self.decode(
      status: 400,
      body: #"{"code":"refresh_token_not_found","message":"Invalid Refresh Token"}"#,
      request: Self.refreshRequest)

    #expect(error.kind == .sessionInvalidated)
    #expect(error.errorCode == .refreshTokenNotFound)
    #expect(error.message == "Invalid Refresh Token")
  }

  @Test
  func versionedUnknownCodeRoundTrips() throws {
    let error = try Self.decode(
      status: 400, body: #"{"code":"added_next_release","message":"Something new"}"#)

    #expect(error.kind == .server)
    #expect(error.errorCode.rawValue == "added_next_release")
  }

  // MARK: OAuth-style shape

  @Test
  func oauthInvalidNonceKeepsTheSpace() throws {
    let error = try Self.decode(
      status: 400,
      body: #"{"error":"invalid nonce","error_description":"Nonces mismatch"}"#,
      request: Self.idTokenRequest)

    #expect(error.kind == .server)
    #expect(error.oauthError == "invalid nonce")
    #expect(error.errorCode == .unknown)
    #expect(error.message == "Nonces mismatch")
  }

  @Test
  func oauthInvalidRequestWithoutDescriptionUsesError() throws {
    let error = try Self.decode(
      status: 400, body: #"{"error":"invalid request"}"#, request: Self.idTokenRequest)

    #expect(error.oauthError == "invalid request")
    #expect(error.message == "invalid request")
  }

  @Test
  func oauthInvalidGrantOnRefreshInvalidatesSession() throws {
    let error = try Self.decode(
      status: 400,
      body: #"{"error":"invalid_grant","error_description":"Invalid Refresh Token"}"#,
      request: Self.refreshRequest)

    #expect(error.kind == .sessionInvalidated)
    #expect(error.oauthError == "invalid_grant")
    #expect(error.message == "Invalid Refresh Token")
  }

  @Test
  func oauthInvalidGrantOutsideRefreshIsAServerError() throws {
    let error = try Self.decode(
      status: 400,
      body: #"{"error":"invalid_grant","error_description":"Bad ID token"}"#,
      request: Self.idTokenRequest)

    #expect(error.kind == .server)
    #expect(error.oauthError == "invalid_grant")
  }

  // MARK: Non-JSON bodies

  @Test
  func htmlServerErrorUsesStatusCodeAndDescription() throws {
    let body = "<html><body>proxy failure</body></html>"
    let error = try Self.decode(status: 500, body: body, contentType: "text/html")

    #expect(error.kind == .server)
    #expect(error.message == "HTTP 500: \(HTTPURLResponse.localizedString(forStatusCode: 500))")
    #expect(error.errorCode == .unexpectedFailure)
    #expect(error.response?.body == Data(body.utf8))
  }

  @Test
  func nonJSONContentTypeIsNotParsed() throws {
    let error = try Self.decode(
      status: 502,
      body: #"{"code":"invalid_credentials","message":"Not from GoTrue"}"#,
      contentType: "text/plain")

    #expect(error.errorCode == .unexpectedFailure)
    #expect(error.message == "HTTP 502: \(HTTPURLResponse.localizedString(forStatusCode: 502))")
  }

  @Test(arguments: [503, 599])
  func emptyServerErrorPreservesStatusCode(statusCode: Int) throws {
    let error = try Self.decode(status: statusCode, body: "", contentType: nil)

    #expect(
      error.message
        == "HTTP \(statusCode): \(HTTPURLResponse.localizedString(forStatusCode: statusCode))")
  }

  @Test(arguments: [400, 499, 600])
  func nonJSONErrorOutsideServerRangeUsesFallbackMessage(statusCode: Int) throws {
    let error = try Self.decode(
      status: statusCode, body: "<html><body>bad request</body></html>", contentType: nil)

    #expect(error.message == "Unexpected response with status code \(statusCode).")
  }

  // MARK: Classification rules

  @Test(arguments: [400, 422])
  func statusDoesNotChangeTheKind(statusCode: Int) throws {
    let error = try Self.decode(
      status: statusCode, body: #"{"code":"session_expired","message":"Invalid login credentials"}"#
    )

    #expect(error.kind == .sessionInvalidated)
    #expect(error.errorCode == .sessionExpired)
  }

  @Test
  func successStatusIsNeverAnError() {
    let error = ErrorDecoder.error(
      response: HTTPTypes.HTTPResponse(status: .ok),
      data: Data(#"{"code":"invalid_credentials","message":"x"}"#.utf8),
      request: Self.signInRequest)

    #expect(error == nil)
  }

  @Test
  func undecodableSuccessBodyIsADecodingError() async throws {
    let sut = AuthClient(
      configuration: AuthClient.Configuration(
        url: URL(string: "http://localhost/auth/v1")!,
        storageKey: uniqueStorageKey(),
        localStorage: InMemoryLocalStorage(),
        http: .init(
          transport: ClosureTransport { _, _ in
            (
              HTTPTypes.HTTPResponse(status: .ok),
              HTTPBody(Data(#"{"error_code":"unexpected"}"#.utf8))
            )
          })
      ))
    try await sut.seedSession(.valid)

    let error = await #expect(throws: AuthError.self) {
      try await sut.mfa.unenroll(params: MFAUnenrollParams(factorId: UUID()))
    }
    #expect(error?.kind == .decoding)
  }

  // MARK: Appendix C

  struct Row: Sendable, CustomTestStringConvertible {
    let status: Int
    let body: String
    let request: HTTPTypes.HTTPRequest
    let kind: AuthError.Kind
    let isRetryable: Bool
    let invalidatesSession: Bool

    init(
      _ status: Int, _ body: String,
      on request: HTTPTypes.HTTPRequest = ErrorDecoderTests.signInRequest,
      kind: AuthError.Kind, isRetryable: Bool = false, invalidatesSession: Bool = false
    ) {
      self.status = status
      self.body = body
      self.request = request
      self.kind = kind
      self.isRetryable = isRetryable
      self.invalidatesSession = invalidatesSession
    }

    var testDescription: String { "\(status) \(body)" }
  }

  static let appendixC: [Row] = [
    Row(
      400, #"{"code":"refresh_token_not_found","message":"m"}"#, on: refreshRequest,
      kind: .sessionInvalidated, invalidatesSession: true),
    Row(
      400, #"{"code":"session_expired","message":"m"}"#, kind: .sessionInvalidated,
      invalidatesSession: true),
    Row(
      400, #"{"code":"refresh_token_already_used","message":"m"}"#, on: refreshRequest,
      kind: .sessionInvalidated, invalidatesSession: true),
    Row(
      403, #"{"code":"session_not_found","message":"m"}"#, kind: .sessionInvalidated,
      invalidatesSession: true),
    Row(
      403, #"{"code":"user_banned","message":"m"}"#, kind: .sessionInvalidated,
      invalidatesSession: true),
    Row(
      400, #"{"error":"invalid_grant","error_description":"m"}"#, on: refreshRequest,
      kind: .sessionInvalidated, invalidatesSession: true),
    Row(409, #"{"code":"conflict","message":"m"}"#, kind: .server, isRetryable: true),
    Row(
      429, #"{"code":"over_request_rate_limit","message":"m"}"#, kind: .server, isRetryable: true),
    Row(
      429, #"{"code":"over_email_send_rate_limit","message":"m"}"#, kind: .server,
      isRetryable: true),
    Row(
      429, #"{"code":"over_sms_send_rate_limit","message":"m"}"#, kind: .server, isRetryable: true),
    Row(500, #"{"code":"unexpected_failure","message":"m"}"#, kind: .server, isRetryable: true),
    Row(520, "", kind: .server, isRetryable: true),
    Row(408, #"{"code":"request_timeout","message":"m"}"#, kind: .server, isRetryable: true),
    Row(403, #"{"code":"bad_jwt","message":"m"}"#, kind: .server),
    Row(422, #"{"code":"weak_password","message":"m"}"#, kind: .server),
    Row(400, #"{"code":"invalid_credentials","message":"m"}"#, kind: .server),
    Row(400, #"{"code":"email_not_confirmed","message":"m"}"#, kind: .server),
    Row(403, #"{"code":"otp_expired","message":"m"}"#, kind: .server),
    Row(400, #"{"code":"captcha_failed","message":"m"}"#, kind: .server),
    Row(400, #"{"code":"validation_failed","message":"m"}"#, kind: .server),
    Row(
      400, #"{"error":"invalid nonce","error_description":"m"}"#, on: idTokenRequest,
      kind: .server),
    Row(404, #"{"code":"flow_state_not_found","message":"m"}"#, kind: .oauthFlowFailed),
    Row(422, #"{"code":"flow_state_expired","message":"m"}"#, kind: .oauthFlowFailed),
    Row(400, #"{"code":"bad_code_verifier","message":"m"}"#, kind: .oauthFlowFailed),
  ]

  @Test(arguments: appendixC)
  func appendixCServerErrorToClientAction(row: Row) throws {
    let error = try Self.decode(status: row.status, body: row.body, request: row.request)

    #expect(error.kind == row.kind)
    #expect(error.isRetryable == row.isRetryable)
    #expect(error.invalidatesSession == row.invalidatesSession)
  }

  @Test
  func transportErrorIsRetryableAndKeepsTheSession() {
    let error = AuthError(
      kind: .transport, message: "offline", underlyingError: URLError(.notConnectedToInternet))

    #expect(error.isRetryable)
    #expect(!error.invalidatesSession)
  }

  @Test
  func decodingErrorIsNotRetryable() {
    let error = AuthError(
      kind: .decoding, message: "bad body",
      response: HTTPErrorResponse(statusCode: 200, headers: [:], body: Data()))

    #expect(!error.isRetryable)
    #expect(!error.invalidatesSession)
  }
}
