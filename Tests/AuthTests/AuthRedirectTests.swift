import Foundation
import Testing

@testable import Auth

@Suite
struct AuthRedirectTests {
  private static let tokens = ImplicitTokens(
    accessToken: "a",
    refreshToken: "r",
    tokenType: "bearer",
    expiresIn: .seconds(3600),
    expiresAt: Date(timeIntervalSince1970: 1_800_003_600)
  )

  private static let implicitFragment =
    "access_token=a&refresh_token=r&token_type=bearer&expires_in=3600&expires_at=1800003600&sb="

  private static let emailChangeAccepted =
    "Confirmation link accepted. Please proceed to confirm link sent to the other email"

  private static let emailChangeAcceptedEncoded =
    "Confirmation+link+accepted.+Please+proceed+to+confirm+link+sent+to+the+other+email"

  private static let linkExpired = AuthError.oauthFlowFailed(
    "Link expired", errorCode: ErrorCode("otp_expired"))

  @Test(arguments: ["inf", "nan", "1e30"])
  func anExpiryOutOfRangeIsAnErrorNotACrash(expiresIn: String) throws {
    let url = try #require(
      URL(
        string:
          "myapp://cb#access_token=a&refresh_token=r&token_type=bearer&expires_in=\(expiresIn)"
      ))

    guard case .error = AuthRedirect.parse(url) else {
      Issue.record("Expected an error for expires_in=\(expiresIn).")
      return
    }
  }

  static let cases: [(String, AuthRedirect?)] = [
    ("myapp://cb?code=abc", .code("abc")),
    ("myapp://cb?code=abc&sb_flow_id=6C69F399-BE1B-467A-9C53-D3753ABDD2DF", .code("abc")),
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
    (
      "myapp://cb?message=\(emailChangeAcceptedEncoded)#message=\(emailChangeAcceptedEncoded)&sb=",
      .emailChangePending(message: emailChangeAccepted)
    ),
    ("myapp://cb#message=\(emailChangeAcceptedEncoded)", nil),
    ("myapp://chat?message=hello", nil),
    ("myapp://chat#message=hello", nil),
    ("myapp://cb#sb=", .error(.oauthFlowFailed("Supabase redirect without a result"))),
    ("myapp://cb#sb", .error(.oauthFlowFailed("Supabase redirect without a result"))),
    (
      "myapp://cb#access_token=a&sb=",
      .error(
        .oauthFlowFailed(
          "The redirect has an access token but no refresh token, token type, or expiry."))
    ),
    ("myapp://cb?code=q#code=f", .code("f")),
    ("myapp://profile?id=42", nil),
    ("https://example.com", nil),
  ]

  @Test(arguments: cases)
  func parse(urlString: String, expected: AuthRedirect?) throws {
    let url = try #require(URL(string: urlString))
    #expect(AuthRedirect.parse(url) == expected)
  }

  @Test(
    arguments: [
      ("com.example.app://callback?code=a", "com.example.app://callback"),
      ("com.example.app://callback/?code=a", "com.example.app://callback"),
      ("com.example.app://callback?code=a", "com.example.app://callback/"),
      ("COM.Example.App://Callback?code=a", "com.example.app://callback"),
      ("com.example.app://callback#access_token=a", "com.example.app://callback?next=home"),
      ("com.example.app:/callback?code=a", "com.example.app:/callback"),
      ("https://example.com/auth/callback?code=a", "https://example.com/auth/callback"),
      ("https://example.com/auth/callback/?code=a", "https://example.com/auth/callback"),
      ("http://localhost:3000/callback?code=a", "http://localhost:3000/callback"),
      ("https://example.com/cb?code=a", "https://example.com:443/cb"),
      ("http://example.com:80/cb?code=a", "http://example.com/cb"),
      ("https://example.com/auth%2Dcb?code=a", "https://example.com/auth-cb"),
    ]
  )
  func aURLReachesItsCallback(url: String, callback: String) throws {
    #expect(
      AuthRedirect.url(try #require(URL(string: url)), reaches: try #require(URL(string: callback)))
    )
  }

  @Test(
    arguments: [
      ("com.example.app://invite?code=a", "com.example.app://callback"),
      ("other.app://callback?code=a", "com.example.app://callback"),
      ("com.example.app://callback/extra?code=a", "com.example.app://callback"),
      ("https://example.com/auth/callback?code=a", "https://example.com/auth"),
      ("https://evil.com/auth/callback?code=a", "https://example.com/auth/callback"),
      ("http://localhost:4000/callback?code=a", "http://localhost:3000/callback"),
      ("http://example.com/callback?code=a", "https://example.com/callback"),
      ("https://example.com:8443/cb?code=a", "https://example.com/cb"),
    ]
  )
  func aURLDoesNotReachAnotherCallback(url: String, callback: String) throws {
    #expect(
      !AuthRedirect.url(
        try #require(URL(string: url)), reaches: try #require(URL(string: callback))))
  }
}
