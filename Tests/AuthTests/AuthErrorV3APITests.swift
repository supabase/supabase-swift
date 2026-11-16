import Foundation
import Testing

@testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct AuthErrorV3APITests {
  private func api(_ code: AuthError.Code) -> AuthError {
    .api(
      message: "API error",
      errorCode: code,
      underlyingData: Data(),
      underlyingResponse: HTTPURLResponse(
        url: URL(string: "http://localhost")!, statusCode: 400, httpVersion: nil, headerFields: nil)!
    )
  }

  @Test
  func kindOfEachCase() {
    #expect(AuthError.sessionMissing.kind == .sessionMissing)
    #expect(AuthError.refreshDiscarded.kind == .refreshDiscarded)
    #expect(AuthError.weakPassword(message: "weak", reasons: ["length"]).kind == .server)
    #expect(api(.invalidCredentials).kind == .server)
    #expect(AuthError.pkceGrantCodeExchange(message: "pkce").kind == .oauthFlowFailed)
    #expect(AuthError.implicitGrantRedirect(message: "implicit").kind == .oauthFlowFailed)
    #expect(AuthError.jwtVerificationFailed(message: "jwt").kind == .jwtVerificationFailed)
  }

  @Test(arguments: [
    AuthError.Code.refreshTokenNotFound, .refreshTokenAlreadyUsed, .sessionExpired,
    .sessionNotFound, .userBanned,
  ])
  func sessionCodesReportSessionInvalidated(code: AuthError.Code) {
    #expect(api(code).kind == .sessionInvalidated)
  }

  @Test(arguments: [AuthError.Code.flowStateNotFound, .flowStateExpired, .badCodeVerifier])
  func flowCodesReportOAuthFlowFailed(code: AuthError.Code) {
    #expect(api(code).kind == .oauthFlowFailed)
  }

  @available(*, deprecated, message: "Covers deprecated cases.")
  @Test
  func kindOfDeprecatedCases() {
    #expect(AuthError.missingExpClaim.kind == .jwtVerificationFailed)
    #expect(AuthError.malformedJWT.kind == .jwtVerificationFailed)
    #expect(AuthError.invalidRedirectScheme.kind == .oauthFlowFailed)
    #expect(AuthError.missingURL.kind == .invalidRequest)
  }

  @Test
  func codeIsNilWhenTheServerSentNone() {
    #expect(api(.invalidCredentials).code == .invalidCredentials)
    #expect(api(AuthError.Code(rawValue: "unknown")).code == nil)
    #expect(AuthError.weakPassword(message: "weak", reasons: []).code == .weakPassword)
    #expect(AuthError.sessionMissing.code == nil)
    #expect(AuthError.refreshDiscarded.code == nil)
    #expect(AuthError.jwtVerificationFailed(message: "jwt").code == nil)
    #expect(AuthError.implicitGrantRedirect(message: "implicit").code == nil)
    #expect(AuthError.pkceGrantCodeExchange(message: "pkce").code == nil)
    #expect(
      AuthError.pkceGrantCodeExchange(message: "pkce", error: "access_denied", code: "otp_expired")
        .code == .otpExpired)
  }

  @Test
  func weakPasswordReasons() {
    #expect(
      AuthError.weakPassword(message: "weak", reasons: ["length", "characters"])
        .weakPasswordReasons == ["length", "characters"])
    #expect(AuthError.sessionMissing.weakPasswordReasons.isEmpty)
    #expect(api(.weakPassword).weakPasswordReasons.isEmpty)
  }

  @Test
  func codeAndKindAreStringLiterals() {
    let literal: AuthError.Code = "invalid_credentials"
    #expect(literal == .invalidCredentials)
    #expect(literal == AuthError.Code(rawValue: "invalid_credentials"))

    let kind: AuthError.Kind = "server"
    #expect(kind == .server)
  }

  @available(*, deprecated, message: "Covers deprecated members.")
  @Test
  func errorCodeIsTheSameTypeAsCode() {
    let old: ErrorCode = ErrorCode("invalid_credentials")
    let new: AuthError.Code = old
    #expect(new == .invalidCredentials)
    #expect(AuthError.sessionMissing.errorCode == ErrorCode.sessionNotFound)
    #expect(api(.unknown).errorCode == .unknown)
  }

  @Test
  func catchByCodeKindAndCase() {
    func thrown(_ error: AuthError) -> String {
      do {
        throw error
      } catch AuthError.Kind.sessionInvalidated {
        return "kind"
      } catch AuthError.Code.invalidCredentials {
        return "code"
      } catch AuthError.sessionMissing {
        return "case"
      } catch let AuthError.api(message, _, _, _) {
        return message
      } catch {
        return "other"
      }
    }

    #expect(thrown(api(.sessionExpired)) == "kind")
    #expect(thrown(api(.invalidCredentials)) == "code")
    #expect(thrown(.sessionMissing) == "case")
    #expect(thrown(api(.emailExists)) == "API error")
    #expect(thrown(.refreshDiscarded) == "other")
    #expect(!(AuthError.Kind.server ~= URLError(.badURL)))
    #expect(!(AuthError.Code.invalidCredentials ~= URLError(.badURL)))
  }

  @Test
  func stringLiteralPatternsOfOtherErrorTypesStillMatch() {
    func name(_ error: AppError) -> String {
      switch error {
      case "offline": "offline"
      case "timeout": "timeout"
      default: "other"
      }
    }

    #expect(name("offline") == "offline")
    #expect(name("timeout") == "timeout")
    #expect(name("unknown") == "other")
  }
}

private struct AppError: Error, Equatable, ExpressibleByStringLiteral {
  let value: String

  init(stringLiteral value: String) {
    self.value = value
  }
}
