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
  struct AuthOptionsOverloadsV3APITests {
    init() {
      Mocker.removeAll()
    }

    // MARK: - signUp

    @available(*, deprecated, message: "Compares with the deprecated v2 method.")
    @Test
    func signUpWithEmailOptions() async throws {
      mock("signup", data: MockData.session)
      let client = V3TestClient()

      let result = try await client.sut.signUp(
        email: "user@example.com", password: "secret",
        options: SignUpOptions(
          userMetadata: ["name": "User"], redirectTo: URL(string: "myapp://welcome"),
          captchaToken: "captcha"))

      let session = try #require(result.session)
      #expect(result == .signedIn(session))
      #expect(result.user == session.user)
      #expect(client.sut.currentSession == session)

      try await client.sut.signUp(
        email: "user@example.com", password: "secret", data: ["name": "User"],
        redirectTo: URL(string: "myapp://welcome"), captchaToken: "captcha")
      #expect(client.body(at: 0) == client.body(at: 1))
      #expect(client.query(at: 0) == client.query(at: 1))
    }

    @Test
    func signUpThatNeedsConfirmation() async throws {
      mock("signup", data: MockData.user)
      let client = V3TestClient()

      let result = try await client.sut.signUp(
        email: "user@example.com", password: "secret", options: SignUpOptions())

      #expect(result == .confirmationRequired(User(fromMockNamed: "user")))
      #expect(result.session == nil)
      #expect(result.user.id == User(fromMockNamed: "user").id)
      #expect(client.sut.currentSession == nil)
      #expect(client.lastBody?["data"] as? NSDictionary == [:])
    }

    @available(*, deprecated, message: "Compares with the deprecated v2 method.")
    @Test
    func signUpWithPhoneOptions() async throws {
      mock("signup", data: MockData.session)
      let client = V3TestClient()

      let result = try await client.sut.signUp(
        phone: "+15555550100", password: "secret",
        options: SignUpOptions(
          userMetadata: ["name": "User"], channel: .whatsapp, captchaToken: "captcha"))
      #expect(result.session != nil)

      try await client.sut.signUp(
        phone: "+15555550100", password: "secret", channel: .whatsapp, data: ["name": "User"],
        captchaToken: "captcha")
      #expect(client.body(at: 0) == client.body(at: 1))
      #expect(client.body(at: 0)?["channel"] as? String == "whatsapp")
    }

    @available(*, deprecated, message: "Covers the deprecated v2 overloads.")
    @Test
    func shortSignUpCallsKeepTheV2Result() async throws {
      mock("signup", data: MockData.session)
      let client = V3TestClient()

      // No type annotation: the `.session` and `.user` patterns exist only on `AuthResponse`.
      let byEmail = try await client.sut.signUp(email: "user@example.com", password: "secret")
      if case .user = byEmail { Issue.record("Expected a session.") }
      guard case .session(let session) = byEmail else { return }
      #expect(session.user == byEmail.user)

      let byPhone = try await client.sut.signUp(phone: "+15555550100", password: "secret")
      guard case .session = byPhone else {
        Issue.record("Expected a session.")
        return
      }

      // A type annotation selects the new overload.
      let typed: SignUpResult = try await client.sut.signUp(
        email: "user@example.com", password: "secret")
      #expect(typed.session != nil)
    }

    @Test
    func signUpResultDecoding() throws {
      let decoder = AuthClient.Configuration.jsonDecoder
      #expect(
        try decoder.decode(SignUpResult.self, from: MockData.session).session
          == Session(fromMockNamed: "session"))
      #expect(
        try decoder.decode(SignUpResult.self, from: MockData.user)
          == .confirmationRequired(User(fromMockNamed: "user")))
    }

    // MARK: - signInWithOTP

    @available(*, deprecated, message: "Compares with the deprecated v2 method.")
    @Test
    func signInWithEmailOTPOptions() async throws {
      mock("otp")
      let client = V3TestClient()

      try await client.sut.signInWithOTP(
        email: "user@example.com",
        options: EmailOTPOptions(
          shouldCreateUser: false, userMetadata: ["name": "User"],
          redirectTo: URL(string: "myapp://otp"), captchaToken: "captcha"))
      try await client.sut.signInWithOTP(
        email: "user@example.com", redirectTo: URL(string: "myapp://otp"),
        shouldCreateUser: false, data: ["name": "User"], captchaToken: "captcha")

      #expect(client.body(at: 0) == client.body(at: 1))
      #expect(client.query(at: 0) == client.query(at: 1))
      #expect(client.body(at: 0)?["create_user"] as? Bool == false)

      // The short call sends the v2 defaults.
      try await client.sut.signInWithOTP(email: "user@example.com")
      #expect(client.lastBody?["create_user"] as? Bool == true)
      #expect(client.lastBody?["email"] as? String == "user@example.com")
    }

    @available(*, deprecated, message: "Compares with the deprecated v2 method.")
    @Test
    func signInWithPhoneOTPOptions() async throws {
      mock("otp", data: Data(#"{"message_id": "SM123"}"#.utf8))
      let client = V3TestClient()

      let messageID = try await client.sut.signInWithOTP(
        phone: "+15555550100",
        options: PhoneOTPOptions(
          shouldCreateUser: false, userMetadata: ["name": "User"], channel: .whatsapp,
          captchaToken: "captcha"))
      #expect(messageID == MessageID(rawValue: "SM123"))

      try await client.sut.signInWithOTP(
        phone: "+15555550100", channel: .whatsapp, shouldCreateUser: false,
        data: ["name": "User"], captchaToken: "captcha")
      #expect(client.body(at: 0) == client.body(at: 1))

      // The short v2 call keeps returning `Void`.
      let nothing: Void = try await client.sut.signInWithOTP(phone: "+15555550100")
      _ = nothing

      let typed: MessageID? = try await client.sut.signInWithOTP(phone: "+15555550100")
      #expect(typed?.rawValue == "SM123")
    }

    @Test
    func signInWithPhoneOTPWithoutAMessageID() async throws {
      mock("otp", data: Data("{}".utf8))
      let client = V3TestClient()

      let messageID = try await client.sut.signInWithOTP(
        phone: "+15555550100", options: PhoneOTPOptions())

      #expect(messageID == nil)
      #expect(client.lastBody?["channel"] as? String == "sms")
      #expect(client.lastBody?["create_user"] as? Bool == true)
    }

    // MARK: - verifyOTP

    @available(*, deprecated, message: "Covers the deprecated v2 overloads.")
    @Test
    func verifyEmailOTP() async throws {
      mock("verify", data: MockData.session)
      let client = V3TestClient()

      let result: VerifyOTPResult = try await client.sut.verifyOTP(
        email: "user@example.com", token: "123456", type: .email)

      guard case .signedIn(let session) = result else {
        Issue.record("Expected a session.")
        return
      }
      #expect(client.sut.currentSession == session)

      // No type annotation: `.user` and `.session` exist only on `AuthResponse`.
      let response = try await client.sut.verifyOTP(
        email: "user@example.com", token: "123456", type: .email)
      #expect(response.user == session.user)
      #expect(response.session == session)
      #expect(client.body(at: 0) == client.body(at: 1))
      #expect(client.query(at: 0) == client.query(at: 1))
    }

    @Test
    func verifyEmailOTPForAPendingEmailChange() async throws {
      mock(
        "verify",
        data: Data(
          #"{"msg": "Confirmation link accepted. Please proceed to confirm link sent to the other email", "code": "200"}"#
            .utf8))
      let client = V3TestClient()

      let result: VerifyOTPResult = try await client.sut.verifyOTP(
        email: "user@example.com", token: "123456", type: .emailChange)

      #expect(
        result
          == .emailChangePending(
            message:
              "Confirmation link accepted. Please proceed to confirm link sent to the other email"))
      #expect(client.sut.currentSession == nil)
    }

    @available(*, deprecated, message: "Covers the deprecated v2 overloads.")
    @Test
    func verifyPhoneOTP() async throws {
      mock("verify", data: MockData.session)
      let client = V3TestClient()

      let session: Session = try await client.sut.verifyOTP(
        phone: "+15555550100", token: "123456", type: .sms)
      #expect(client.sut.currentSession == session)

      // No type annotation: `.session` exists only on `AuthResponse`.
      let response = try await client.sut.verifyOTP(
        phone: "+15555550100", token: "123456", type: .sms)
      #expect(response.session == session)
      #expect(client.body(at: 0) == client.body(at: 1))
    }

    // MARK: - resend

    @available(*, deprecated, message: "Compares with the deprecated v2 method.")
    @Test
    func resendEmailOptions() async throws {
      mock("resend")
      let client = V3TestClient()

      try await client.sut.resend(
        email: "user@example.com", type: .signup,
        options: ResendEmailOptions(
          redirectTo: URL(string: "myapp://confirm"), captchaToken: "captcha"))
      try await client.sut.resend(
        email: "user@example.com", type: .signup,
        emailRedirectTo: URL(string: "myapp://confirm"), captchaToken: "captcha")

      #expect(client.body(at: 0) == client.body(at: 1))
      #expect(client.query(at: 0) == client.query(at: 1))

      try await client.sut.resend(email: "user@example.com", type: .signup)
      #expect(client.lastBody?["type"] as? String == "signup")
    }

    @available(*, deprecated, message: "Covers the deprecated v2 overloads.")
    @Test
    func resendPhoneOptions() async throws {
      mock("resend", data: Data(#"{"message_id": "SM123"}"#.utf8))
      let client = V3TestClient()

      let messageID = try await client.sut.resend(
        phone: "+15555550100", type: .sms, options: ResendPhoneOptions(captchaToken: "captcha"))
      #expect(messageID == MessageID(rawValue: "SM123"))

      // No type annotation: `.messageId` exists only on `ResendMobileResponse`.
      let response = try await client.sut.resend(
        phone: "+15555550100", type: .sms, captchaToken: "captcha")
      #expect(response.messageId == "SM123")
      #expect(client.body(at: 0) == client.body(at: 1))

      let short = try await client.sut.resend(phone: "+15555550100", type: .sms)
      #expect(short.messageId == "SM123")

      let typed: MessageID? = try await client.sut.resend(phone: "+15555550100", type: .sms)
      #expect(typed?.rawValue == "SM123")
    }
  }
}
