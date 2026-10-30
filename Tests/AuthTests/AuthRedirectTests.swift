import Foundation
import Testing

@testable import Auth

@Suite
struct AuthRedirectTests {
  private static let flowID = UUID(uuidString: "6C69F399-BE1B-467A-9C53-D3753ABDD2DF")!

  private static let tokens = ImplicitTokens(
    accessToken: "a",
    refreshToken: "r",
    tokenType: "bearer",
    expiresIn: 3600,
    expiresAt: 1_800_003_600
  )

  private static let implicitFragment =
    "access_token=a&refresh_token=r&token_type=bearer&expires_in=3600&expires_at=1800003600&sb="

  private static let linkExpired = AuthError.oauthFlowFailed(
    "Link expired", errorCode: ErrorCode("otp_expired"))

  static let cases: [(String, AuthRedirect?)] = [
    ("myapp://cb?code=abc", .code("abc", flowID: nil)),
    ("myapp://cb?code=abc&sb_flow_id=\(flowID.uuidString)", .code("abc", flowID: flowID)),
    ("myapp://cb?code=abc&sb_flow_id=not-a-uuid", .code("abc", flowID: nil)),
    ("myapp://cb#\(implicitFragment)", .implicit(tokens, type: nil)),
    ("myapp://cb#\(implicitFragment)&type=recovery", .implicit(tokens, type: .recovery)),
    (
      "myapp://cb#error=access_denied&error_code=otp_expired&error_description=Link+expired&sb=",
      .error(linkExpired)
    ),
    (
      "myapp://cb?error=access_denied&error_code=otp_expired&error_description=Link+expired&sb=",
      .error(linkExpired)
    ),
    (
      "myapp://cb?error=access_denied",
      .error(.oauthFlowFailed("access_denied", errorCode: .unknown))
    ),
    (
      "myapp://cb#error=access_denied",
      .error(.oauthFlowFailed("access_denied", errorCode: .unknown))
    ),
    (
      "myapp://cb?error=access_denied&error_description=User+denied+access",
      .error(.oauthFlowFailed("User denied access", errorCode: .unknown))
    ),
    (
      "myapp://cb#error_code=otp_expired",
      .error(
        .oauthFlowFailed("The redirect reports an error.", errorCode: ErrorCode("otp_expired")))
    ),
    (
      "myapp://cb?message=Confirmation+link+accepted&sb=",
      .emailChangePending(message: "Confirmation link accepted")
    ),
    ("myapp://cb#sb=", .error(.oauthFlowFailed("Supabase redirect without a result"))),
    ("myapp://cb#sb", .error(.oauthFlowFailed("Supabase redirect without a result"))),
    (
      "myapp://cb#access_token=a&sb=",
      .error(
        .oauthFlowFailed(
          "The redirect has an access token but no refresh token, token type, or expiry."))
    ),
    ("myapp://cb?code=q#code=f", .code("f", flowID: nil)),
    ("myapp://profile?id=42", nil),
    ("https://example.com", nil),
  ]

  @Test(arguments: cases)
  func parse(urlString: String, expected: AuthRedirect?) throws {
    let url = try #require(URL(string: urlString))
    #expect(AuthRedirect.parse(url) == expected)
  }

  @Test
  func errorMessageContainsDescription() throws {
    let url = try #require(
      URL(
        string:
          "myapp://cb#error=access_denied&error_code=otp_expired&error_description=Link+expired&sb="
      ))
    guard case .error(let error) = AuthRedirect.parse(url) else {
      Issue.record("Expected .error")
      return
    }
    #expect(error.kind == .oauthFlowFailed)
    #expect(error.errorCode == ErrorCode("otp_expired"))
    #expect(error.message.contains("Link expired"))
  }

  @Test
  func credentialIsTheCodeOrTheAccessToken() {
    #expect(AuthRedirect.code("abc", flowID: nil).credential == "abc")
    #expect(AuthRedirect.implicit(Self.tokens, type: nil).credential == "a")
    #expect(AuthRedirect.emailChangePending(message: "m").credential == nil)
    #expect(AuthRedirect.error(Self.linkExpired).credential == nil)
  }
}
