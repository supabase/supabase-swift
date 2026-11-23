//
//  AuthMFAIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 31/10/26.
//

import ConcurrencyExtras
import Crypto
import CustomDump
import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@testable import Auth

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct AuthMFAIntegrationTests {
  let auth = try! AuthClient(
    configuration: AuthClient.Configuration(
      url: URL(string: "\(DotEnv.supabaseURL)/auth/v1")!,
      storageKey: "sb-test-\(UUID().uuidString)-auth-token",
      headers: [
        .apikey: DotEnv.supabasePublishableKey,
        .authorization: "Bearer \(DotEnv.supabasePublishableKey)",
      ],
      storage: InMemoryTestStorage()
    )
  )

  @Test
  func totpEnrollVerifyAndUnenroll() async throws {
    try await signUp()

    #expect(try await auth.mfa.factors().all.isEmpty)

    let enrollment = try await auth.mfa.enrollTOTP(issuer: "supabase.com", friendlyName: "Phone")
    #expect(enrollment.friendlyName == "Phone")
    #expect(enrollment.uri.hasPrefix("otpauth://totp/"))

    let enrolled = try await auth.mfa.factors()
    expectNoDifference(enrolled.verified, [])
    expectNoDifference(enrolled.unverified.map(\.id), [enrollment.id])
    expectNoDifference(enrolled.unverified.map(\.factorType), [.totp])
    #expect(enrolled.unverified.first?.lastChallengedAt == nil)
    #expect(enrolled.unverified.first?.phone == nil)

    let before = try await auth.mfa.assuranceLevel()
    expectNoDifference(before.currentLevel, .aal1)
    expectNoDifference(before.nextLevel, .aal1)

    let previousRefreshToken = try #require(auth.currentSession?.refreshToken)
    let events = auth.events()

    let session = try await auth.mfa.challengeAndVerify(
      factorID: enrollment.id, code: try totpCode(secret: enrollment.secret))

    let received = try await withTimeout(.seconds(5)) {
      await events.prefix(2).collect()
    }
    expectNoDifference(received.map(\.event), [.initialSession, .mfaChallengeVerified])
    expectNoDifference(auth.currentSession, session)
    #expect(session.refreshToken != previousRefreshToken)

    let after = try await auth.mfa.assuranceLevel()
    expectNoDifference(after.currentLevel, .aal2)
    expectNoDifference(after.nextLevel, .aal2)
    #expect(after.currentAuthenticationMethods.map(\.method).contains(.totp))
    #expect(after.currentAuthenticationMethods.allSatisfy { $0.timestamp <= Date() })

    let verified = try await auth.mfa.factors()
    expectNoDifference(verified.verified.map(\.id), [enrollment.id])
    #expect(verified.verified.first?.lastChallengedAt != nil)
    expectNoDifference(verified.unverified, [])

    let removed = try await auth.mfa.unenroll(factorID: enrollment.id)
    expectNoDifference(removed.id, enrollment.id)

    #expect(try await auth.mfa.factors().all.isEmpty)
  }

  @Test
  func challengeExpiresInTheFuture() async throws {
    try await signUp()

    let enrollment = try await auth.mfa.enrollTOTP()
    let challenge = try await auth.mfa.challenge(factorID: enrollment.id)

    expectNoDifference(challenge.factorType, .totp)
    #expect(challenge.expiresAt > Date())
  }

  @Test
  func verifyWithAWrongCodeFailsAndKeepsTheSession() async throws {
    try await signUp()
    let session = try #require(auth.currentSession)

    let enrollment = try await auth.mfa.enrollTOTP()
    let challenge = try await auth.mfa.challenge(factorID: enrollment.id)

    let error = await #expect(throws: AuthError.self) {
      try await auth.mfa.verify(
        factorID: enrollment.id, challengeID: challenge.id, code: "000000")
    }
    expectNoDifference(error?.code, .mfaVerificationFailed)
    expectNoDifference(auth.currentSession, session)
  }

  @Test
  func assuranceLevelWithoutASessionThrowsSessionMissing() async throws {
    try await signUp()
    try await auth.signOut()

    let error = await #expect(throws: AuthError.self) {
      try await auth.mfa.assuranceLevel()
    }
    expectNoDifference(error?.kind, .sessionMissing)
  }

  private func signUp() async throws {
    let email = "\(UUID().uuidString.lowercased())@supabase.com"
    let result = try await auth.signUp(email: email, password: "The.Pa55word!")
    _ = try #require(result.session, "Expected a session from sign-up, got \(result)")
  }
}
