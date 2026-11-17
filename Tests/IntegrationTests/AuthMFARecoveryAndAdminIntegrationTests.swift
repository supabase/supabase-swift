//
//  AuthMFARecoveryAndAdminIntegrationTests.swift
//  IntegrationTests
//
//  Created by Guilherme Souza on 16/11/26.
//

import CustomDump
import Foundation
import TestHelpers
import Testing

@testable import Auth

/// MFA recovery codes and the admin MFA, OAuth client and user lookups, against the local stack.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct AuthMFARecoveryAndAdminIntegrationTests {
  static let password = "The.Pa55word!"

  let auth = try! AuthClientIntegrationTests.makeClient()
  let admin = AuthClientIntegrationTests.makeAdminClient()

  // MARK: - Recovery codes

  /// The local stack refuses to enroll recovery codes, and the CLI has no setting to allow it, so
  /// this checks the refusal: the request reaches Auth, and the SDK surfaces its error code.
  @Test
  func recoveryCodesEnrollmentIsRefusedOnTheLocalStack() async throws {
    _ = try await auth.signUp(email: mockEmail(), password: Self.password)

    let missing = await #expect(throws: AuthError.self) {
      try await auth.mfa.recoveryCodes.status()
    }
    #expect(missing?.code?.rawValue == "mfa_factor_not_found")

    try await verifyTOTPFactor()
    let refused = await #expect(throws: AuthError.self) {
      try await auth.mfa.recoveryCodes.generate(friendlyName: "Backup codes")
    }
    #expect(refused?.code?.rawValue == "mfa_recovery_codes_enroll_not_enabled")
  }

  @Test(
    .disabled(
      """
      Recovery codes are an experimental Auth feature. The local stack refuses to enroll them \
      (mfa_recovery_codes_enroll_not_enabled), and the CLI has no setting to allow it.
      """))
  func recoveryCodesGenerateVerifyRegenerateAndUnenroll() async throws {
    let email = mockEmail()
    _ = try await auth.signUp(email: email, password: Self.password)
    try await verifyTOTPFactor()

    let generated = try await auth.mfa.recoveryCodes.generate(friendlyName: "Backup codes")
    #expect(generated.friendlyName == "Backup codes")
    #expect(generated.codes.count == generated.total)
    #expect(Set(generated.codes).count == generated.total)
    let status = try await auth.mfa.recoveryCodes.status()
    expectNoDifference(
      status,
      AuthMFARecoveryCodesStatusResponse(
        id: generated.id, total: generated.total, remaining: generated.total))

    // A new sign-in starts at aal1; a recovery code takes it to aal2 and is then spent.
    let other = try AuthClientIntegrationTests.makeClient()
    try await other.signIn(email: email, password: Self.password)
    let before = try await other.mfa.assuranceLevel()
    expectNoDifference(before.currentLevel, .aal1)
    try await other.mfa.recoveryCodes.verify(code: generated.codes[0])
    let after = try await other.mfa.assuranceLevel()
    expectNoDifference(after.currentLevel, .aal2)
    #expect(try await other.mfa.recoveryCodes.status().remaining == generated.total - 1)
    await #expect(throws: AuthError.self) {
      try await other.mfa.recoveryCodes.verify(code: generated.codes[0])
    }

    let regenerated = try await auth.mfa.recoveryCodes.regenerate()
    #expect(regenerated.id == generated.id)
    #expect(Set(regenerated.codes).isDisjoint(with: generated.codes))
    #expect(try await auth.mfa.recoveryCodes.status().remaining == regenerated.total)
    await #expect(throws: AuthError.self) {
      try await other.mfa.recoveryCodes.verify(code: generated.codes[1])
    }

    let removed = try await auth.mfa.recoveryCodes.unenroll()
    #expect(removed.id == generated.id)
    await #expect(throws: AuthError.self) { try await auth.mfa.recoveryCodes.status() }
  }

  // MARK: - Admin MFA

  @Test
  func adminListsAndDeletesAUsersFactors() async throws {
    _ = try await auth.signUp(email: mockEmail(), password: Self.password)
    let userID = try await auth.session().user.id
    let enrollment = try await auth.mfa.enrollTOTP(friendlyName: "Admin listed")

    let factors = try await admin.mfa.listFactors(forUser: userID)
    expectNoDifference(factors.map(\.id), [enrollment.id])
    expectNoDifference(factors.map(\.factorType), [.totp])

    try await admin.mfa.deleteFactor(id: enrollment.id, forUser: userID)
    #expect(try await admin.mfa.listFactors(forUser: userID).isEmpty)
    #expect(try await auth.mfa.factors().all.isEmpty)

    try await admin.deleteUser(id: userID)
  }

  // MARK: - Admin users

  @Test
  func adminFetchesAUserByID() async throws {
    let email = mockEmail()
    let created = try await admin.createUser(
      AdminCreateUser(email: email, password: Self.password, confirmsEmail: true))

    let fetched = try await admin.user(id: created.id)
    #expect(fetched.id == created.id)
    #expect(fetched.email == email)
    #expect(fetched.emailConfirmedAt != nil)

    try await admin.deleteUser(id: created.id)
    let error = await #expect(throws: AuthError.self) { try await admin.user(id: created.id) }
    #expect(error?.code == .userNotFound)
  }

  // MARK: - Admin OAuth clients

  @Test
  func adminFetchesUpdatesAndRegeneratesAnOAuthClient() async throws {
    let created = try await admin.oauth.createClient(
      CreateOAuthClient(
        clientName: "Gaps Client", redirectURIs: [URL(string: "https://example.com/callback")!])
    )

    let fetched = try await admin.oauth.client(id: created.clientID)
    #expect(fetched.clientID == created.clientID)
    #expect(fetched.clientName == "Gaps Client")
    #expect(fetched.redirectURIs == [URL(string: "https://example.com/callback")!])

    let updated = try await admin.oauth.updateClient(
      id: created.clientID,
      UpdateOAuthClient(
        clientName: "Renamed Client",
        redirectURIs: [URL(string: "https://example.com/other")!])
    )
    #expect(updated.clientName == "Renamed Client")
    #expect(updated.redirectURIs == [URL(string: "https://example.com/other")!])
    #expect(try await admin.oauth.client(id: created.clientID).clientName == "Renamed Client")

    let regenerated = try await admin.oauth.regenerateClientSecret(id: created.clientID)
    #expect(regenerated.clientID == created.clientID)
    let secret = try #require(regenerated.clientSecret)
    #expect(!secret.isEmpty)
    #expect(secret != created.clientSecret)

    try await admin.oauth.deleteClient(id: created.clientID)
  }

  // MARK: - Helpers

  /// Enrolls a TOTP factor for the signed-in user and verifies it, so the session is at aal2.
  private func verifyTOTPFactor() async throws {
    let enrollment = try await auth.mfa.enrollTOTP(friendlyName: "Authenticator")
    try await auth.mfa.challengeAndVerify(
      factorID: enrollment.id, code: try totpCode(secret: enrollment.secret))
    let level = try await auth.mfa.assuranceLevel()
    expectNoDifference(level.currentLevel, .aal2)
  }

  private func mockEmail() -> String {
    "mfa-admin-\(UUID().uuidString.lowercased())@supabase.com"
  }
}
