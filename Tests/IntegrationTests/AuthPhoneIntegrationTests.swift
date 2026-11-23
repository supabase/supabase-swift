//
//  AuthPhoneIntegrationTests.swift
//  IntegrationTests
//
//  Created by Guilherme Souza on 16/11/26.
//

import CustomDump
import Foundation
import TestHelpers
import Testing

@testable import Auth

/// Phone sign-up, phone OTP and phone MFA enrollment against the local stack.
///
/// Auth sends no SMS to the `[auth.sms.test_otp]` numbers in `config.toml` and accepts
/// ``testCode`` for them. Each test uses its own number, so `max_frequency` never throttles one
/// test with another's send.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct AuthPhoneIntegrationTests {
  static let testCode = "123456"

  let auth = try! AuthClientIntegrationTests.makeClient()
  let admin = AuthClientIntegrationTests.makeAdminClient()

  /// Phone confirmations are on, so sign-up sends a code and returns no session. `resend` sends
  /// the code again, and `verifyOTP` confirms the number and signs in.
  @Test
  func signUpWithPhoneResendTheCodeAndVerifyIt() async throws {
    let phone = "15550000003"
    try await deleteUsers(withPhone: phone)

    let result = try await auth.signUp(phone: phone, password: "The.Pa55word!")
    guard case .confirmationRequired(let user) = result else {
      Issue.record("Expected .confirmationRequired, got \(result)")
      return
    }
    #expect(user.phone == phone)
    #expect(user.phoneConfirmedAt == nil)
    #expect(auth.currentSession == nil)

    // `max_frequency` is 5 seconds per number.
    try await Task.sleep(for: .seconds(6))
    try await auth.resend(phone: phone, type: .sms)
    let session = try await auth.verifyOTP(phone: phone, token: Self.testCode, type: .sms)

    #expect(session.user.id == user.id)
    #expect(session.user.phoneConfirmedAt != nil)
    #expect(auth.currentSession == session)
    try await admin.deleteUser(id: user.id)
  }

  @Test
  func signInWithOTPAndVerifyIt() async throws {
    let phone = "15550000001"

    try await auth.signInWithOTP(phone: phone)
    let session = try await auth.verifyOTP(phone: phone, token: Self.testCode, type: .sms)

    #expect(session.user.phone == phone)
    #expect(auth.currentSession == session)
  }

  @Test
  func verifyOTPRejectsAWrongCode() async throws {
    let phone = "15550000002"

    try await auth.signInWithOTP(phone: phone)
    await #expect(throws: AuthError.self) {
      try await auth.verifyOTP(phone: phone, token: "000000", type: .sms)
    }
    #expect(auth.currentSession == nil)
  }

  /// Auth does not use the test numbers for an MFA challenge: it always sends a real SMS, which
  /// the placeholder Twilio account cannot do. So the test stops at the enrollment, which sends
  /// nothing.
  @Test
  func enrollAndUnenrollAPhoneFactor() async throws {
    _ = try await auth.signUp(email: mockEmail(), password: "The.Pa55word!")

    let enrollment = try await auth.mfa.enrollPhone("15550000004", friendlyName: "Work phone")
    #expect(enrollment.phone == "15550000004")
    #expect(enrollment.friendlyName == "Work phone")

    let factors = try await auth.mfa.factors()
    expectNoDifference(factors.verified, [])
    expectNoDifference(factors.unverified.map(\.id), [enrollment.id])
    expectNoDifference(factors.unverified.map(\.factorType), [.phone])
    expectNoDifference(factors.unverified.map(\.phone), ["15550000004"])

    try await auth.mfa.unenroll(factorID: enrollment.id)
    #expect(try await auth.mfa.factors().all.isEmpty)
  }

  private func deleteUsers(withPhone phone: String) async throws {
    for try await user in admin.users(pageSize: 1000) where user.phone == phone {
      try await admin.deleteUser(id: user.id)
    }
  }

  private func mockEmail() -> String {
    "phone-\(UUID().uuidString.lowercased())@supabase.com"
  }
}
