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
import Helpers
import TestHelpers
import Testing

@testable import Auth

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct AuthMFAIntegrationTests {
  let auth = AuthClient(
    configuration: AuthClient.Configuration(
      url: URL(string: "\(DotEnv.supabaseURL)/auth/v1")!,
      headers: [
        "apikey": DotEnv.supabasePublishableKey,
        "Authorization": "Bearer \(DotEnv.supabasePublishableKey)",
      ],
      localStorage: InMemoryLocalStorage()
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
    expectNoDifference(verified.unverified, [])

    try await auth.mfa.unenroll(factorID: enrollment.id)

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
    expectNoDifference(error?.errorCode, .mfaVerificationFailed)
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

  /// RFC 6238 with the defaults GoTrue uses: SHA-1, 6 digits, a 30-second step.
  private func totpCode(secret: String, at date: Date = Date()) throws -> String {
    let key = try #require(base32Decode(secret))
    var counter = UInt64(date.timeIntervalSince1970 / 30).bigEndian
    let message = withUnsafeBytes(of: &counter) { Data($0) }

    let mac = Array(
      HMAC<Insecure.SHA1>.authenticationCode(for: message, using: SymmetricKey(data: key)))
    let offset = Int(mac[mac.count - 1] & 0x0f)
    let truncated =
      (UInt32(mac[offset] & 0x7f) << 24) | (UInt32(mac[offset + 1]) << 16)
      | (UInt32(mac[offset + 2]) << 8) | UInt32(mac[offset + 3])

    return String(format: "%06u", truncated % 1_000_000)
  }

  private func base32Decode(_ string: String) -> Data? {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    var buffer: UInt32 = 0
    var bitCount = 0
    var bytes: [UInt8] = []

    for character in string.uppercased() where character != "=" {
      guard let value = alphabet.firstIndex(of: character) else { return nil }
      buffer = (buffer << 5) | UInt32(value)
      bitCount += 5
      if bitCount >= 8 {
        bitCount -= 8
        bytes.append(UInt8((buffer >> UInt32(bitCount)) & 0xff))
      }
    }

    return Data(bytes)
  }
}
