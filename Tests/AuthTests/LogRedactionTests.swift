import Logging
import TestHelpers
import Testing

@testable import Auth

@Suite
struct LogRedactionTests {
  static let jwt =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjMifQ.c2lnbmF0dXJlLXZhbHVl"

  @Test
  func masksJWTsWhereverTheyAppear() {
    #expect(LogRedaction.redact("Bearer \(Self.jwt) sent") == "Bearer <redacted> sent")
    #expect(LogRedaction.redact(Self.jwt) == "<redacted>")
  }

  @Test(
    arguments: [
      ("refresh_token: r-secret-1", "refresh_token: <redacted>"),
      ("refresh_token=r-secret-1&type=x", "refresh_token=<redacted>&type=x"),
      (#"{"refresh_token" : "r-secret-1"}"#, #"{"refresh_token" : "<redacted>"}"#),
      (
        #"Session(refreshToken: "r-secret-1", expiresIn: 3600.0)"#,
        #"Session(refreshToken: "<redacted>", expiresIn: 3600.0)"#
      ),
      (#"providerToken: Optional("gho_secret")"#, #"providerToken: Optional("<redacted>")"#),
      ("code_verifier=v-secret-1", "code_verifier=<redacted>"),
      ("codeVerifier: v-secret-1", "codeVerifier: <redacted>"),
      ("email_otp: 123456", "email_otp: <redacted>"),
      ("token = 654321", "token = <redacted>"),
      ("id_token=idt-secret", "id_token=<redacted>"),
      ("password: hunter2", "password: <redacted>"),
      ("auth_code=c-secret-1", "auth_code=<redacted>"),
      ("authCode: c-secret-1", "authCode: <redacted>"),
    ]
  )
  func masksTheValueOfASensitiveKey(input: String, expected: String) {
    #expect(LogRedaction.redact(input) == expected)
  }

  @Test(arguments: LogRedaction.sensitiveKeys.sorted())
  func theKeyListAndThePatternAgree(key: String) {
    #expect(LogRedaction.redact("\(key)=value-9") == "\(key)=<redacted>")
    #expect(LogRedaction.isSensitive(key: key))
  }

  @Test
  func stripsTheQueryAndFragmentFromAnyURL() {
    #expect(
      LogRedaction.redact("Request: GET https://x.supabase.co/auth/v1/verify?token=abc&type=signup")
        == "Request: GET https://x.supabase.co/auth/v1/verify")
    #expect(
      LogRedaction.redact("redirect to myapp://callback#access_token=abc&expires_in=3600")
        == "redirect to myapp://callback")
    #expect(
      LogRedaction.redact("opened https://x.supabase.co/auth/v1/user, then closed")
        == "opened https://x.supabase.co/auth/v1/user, then closed")
  }

  @Test(
    arguments: [
      "session expired, auto refresh disabled; status code: 401 for user_id 42",
      "AuthError(server): Invalid Refresh Token: Refresh Token Not Found",
      "Invalid Refresh Token: Already Used",
      "Password: Weak and short",
    ]
  )
  func leavesOrdinaryTextAlone(text: String) {
    #expect(LogRedaction.redact(text) == text)
  }

  @Test
  func masksSecretsInJSONThatEscapesItsSlashesAndQuotes() {
    #expect(
      LogRedaction.redact(#"{"url" : "https:\/\/idp.example\/authorize?state=s-1&code=c-1"}"#)
        == #"{"url" : "https:\/\/idp.example\/authorize"}"#)
    #expect(
      LogRedaction.redact(#"body: {\"refresh_token\":\"r-secret-1\"}"#)
        == #"body: {\"refresh_token\":\"<redacted>\"}"#)
  }
}

@Suite
struct RedactingLogHandlerTests {
  private let recorder = LogRecorder()

  @Test
  func redactsTheMessageBeforeTheBaseHandlerSeesIt() {
    let logger = recorder.makeLogger().redactingSecrets()

    logger.warning("refresh failed for refresh_token=r-secret-1")

    #expect(recorder.entries == ["refresh failed for refresh_token=<redacted>"])
  }

  @Test
  func redactsPerCallAndLoggerMetadata() {
    var logger = recorder.makeLogger().redactingSecrets()
    logger[metadataKey: "client_id"] = "1"
    logger[metadataKey: "access_token"] = "a-secret-1"

    logger.error("failed", metadata: ["url": "https://x.co/verify?token=t-secret-1"])

    #expect(
      recorder.entries == ["failed access_token=<redacted> client_id=1 url=https://x.co/verify"])
  }

  @Test
  func redactsNestedMetadata() {
    let logger = recorder.makeLogger().redactingSecrets()

    logger.info(
      "nested",
      metadata: [
        "dictionary": .dictionary(["refresh_token": "r-secret-1", "ok": "fine"]),
        "array": .array(["refresh_token=r-secret-2"]),
      ])

    let entry = recorder.entries.joined()
    #expect(!entry.contains("r-secret"))
    #expect(entry.contains("fine"))
  }

  @Test
  func keepsTheBaseLoggerLevel() {
    var base = recorder.makeLogger()
    base.logLevel = .error

    let logger = base.redactingSecrets()
    logger.warning("dropped")
    logger.error("kept")

    #expect(recorder.entries == ["kept"])
  }
}
