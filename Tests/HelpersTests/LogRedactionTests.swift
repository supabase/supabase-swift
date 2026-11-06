import Foundation
import Logging
import TestHelpers
import Testing

@testable import Helpers

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
  func masksSecretAPIKeys() {
    #expect(
      LogRedaction.redact("Authorization: Bearer sb_secret_AbC-123_xyz sent")
        == "Authorization: Bearer <redacted> sent")
    #expect(LogRedaction.redact("apiKey: sb_publishable_1") == "apiKey: <redacted>")
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
struct LogRedactionSummaryTests {
  @Test
  func summarizesAnErrorByDomainAndCodeOnly() {
    let error = URLError(
      .timedOut, userInfo: [NSURLErrorFailingURLStringErrorKey: "https://x.co/?token=t-1"])

    #expect(LogRedaction.summary(of: error) == "NSURLErrorDomain \(URLError.timedOut.rawValue)")
  }

  @Test
  func summarizesADecodingErrorByItsCaseAndPathWithoutTheValue() throws {
    struct Row: Decodable { let id: Int }
    let error = try #require(
      throws: DecodingError.self,
      performing: {
        try JSONDecoder().decode([Row].self, from: Data(#"[{"id":"s-secret-1"}]"#.utf8))
      }
    )

    #expect(LogRedaction.summary(of: error) == "DecodingError.typeMismatch at 'Index 0.id'")
  }

  @Test
  func summarizesAnEncodingErrorByItsPathWithoutTheValue() throws {
    let error = try #require(
      throws: EncodingError.self,
      performing: { try JSONEncoder().encode(["access_token": Double.nan]) }
    )

    #expect(LogRedaction.summary(of: error) == "EncodingError.invalidValue at 'access_token'")
  }

  @Test
  func keepsTheDescriptionOfAnErrorThatDoesNotLeak() {
    struct Closed: Error, CustomStringConvertible {
      var description: String { "closed with code 4000" }
    }

    #expect(LogRedaction.summary(of: Closed()) == "closed with code 4000")
  }

  @Test(arguments: ["signedURL", "signedUrl", "url", "action_link", "refresh_token", "otp"])
  func redactsSensitiveAndLinkKeysInJSON(key: String) {
    #expect(LogRedaction.isSensitive(jsonKey: key))
  }

  @Test(arguments: ["path", "id", "status"])
  func keepsOtherJSONKeys(key: String) {
    #expect(!LogRedaction.isSensitive(jsonKey: key))
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
  func redactsMetadataThatIsOnlyConvertibleToAString() {
    struct Leaky: CustomStringConvertible, Sendable {
      var description: String { "refresh_token=r-secret-1" }
    }
    let logger = recorder.makeLogger().redactingSecrets()

    logger.info("converted", metadata: ["value": .stringConvertible(Leaky())])

    #expect(recorder.entries == ["converted value=refresh_token=<redacted>"])
  }

  @Test
  func redactsAndReadsBackMetadataSetOnTheHandler() {
    var handler = RedactingLogHandler(wrapping: recorder.makeLogger())

    handler.metadata = ["access_token": "a-secret-1", "client_id": "1"]
    handler[metadataKey: "url"] = "https://x.co/verify?token=t-secret-1"

    #expect(handler.metadata["access_token"] == "<redacted>")
    #expect(handler[metadataKey: "client_id"] == "1")
    #expect(handler[metadataKey: "url"] == "https://x.co/verify")
    handler[metadataKey: "url"] = nil
    #expect(handler[metadataKey: "url"] == nil)
  }

  @Test
  func changingTheLevelOfTheWrapperChangesTheBaseLevel() {
    var logger = recorder.makeLogger().redactingSecrets()

    logger.logLevel = .error
    logger.warning("dropped")
    logger.error("kept")

    #expect(logger.logLevel == .error)
    #expect(recorder.entries == ["kept"])
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

  @Test
  func wrappingTwiceKeepsASingleRedactingHandler() throws {
    let logger = recorder.makeLogger().redactingSecrets().redactingSecrets()

    let handler = try #require(logger.handler as? RedactingLogHandler)
    #expect(!(handler.base.handler is RedactingLogHandler))
    logger.warning("refresh_token=r-secret-1")
    #expect(recorder.entries == ["refresh_token=<redacted>"])
  }
}

@Suite
struct LogRecorderTests {
  @Test
  func recordsHandlerMetadataBesideTheMessage() {
    let recorder = LogRecorder()
    var logger = recorder.makeLogger()

    logger[metadataKey: "system"] = "auth"
    logger.info("hello", metadata: ["id": "1"])

    #expect(logger[metadataKey: "system"] == "auth")
    #expect(recorder.entries == ["hello id=1 system=auth"])
  }
}
