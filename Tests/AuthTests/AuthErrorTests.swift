//
//  AuthErrorTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 29/08/24.
//

import Foundation
import HTTPTypes
import Testing

@_spi(Experimental) @testable import Auth

@Suite
struct AuthErrorTests {
  @Test
  func sessionMissingStatic() {
    let error = AuthError.sessionMissing

    #expect(error.kind == .sessionMissing)
    #expect(error.code == nil)
    #expect(error.message == "Auth session missing.")
    #expect(error.weakPasswordReasons.isEmpty)
    #expect(error.response == nil)
  }

  @Test
  func codeIsNilWhenTheServerSentNone() {
    let error = AuthError(kind: .oauthFlowFailed, message: "Implicit grant failure")

    #expect(error.code == nil)
    #expect(error.weakPasswordReasons.isEmpty)
    #expect(error.errorDescription == "Implicit grant failure")
  }

  @Test
  func clientSideFailuresHaveNoCode() {
    #expect(AuthError.oauthFlowFailed("No redirect URL configured").code == nil)
    #expect(AuthError.jwtVerificationFailed("expired").code == nil)
  }

  @Test
  func oauthFlowFailedIsClientSide() {
    let error = AuthError.oauthFlowFailed("No redirect URL configured")

    #expect(error.kind == .oauthFlowFailed)
    #expect(error.response == nil)
    #expect(error.errorDescription == "No redirect URL configured")
  }

  @Test
  func catchMatchesCode() {
    func signIn() throws {
      throw AuthError(kind: .server, message: "Invalid", code: .invalidCredentials)
    }

    var caught = false
    do {
      try signIn()
    } catch AuthError.Code.emailNotConfirmed {
      Issue.record("Matched the wrong code")
    } catch AuthError.Code.invalidCredentials {
      caught = true
    } catch {
      Issue.record("Expected AuthError.Code.invalidCredentials, got \(error)")
    }
    #expect(caught)
  }

  @Test
  func catchMatchesKind() {
    func refresh() throws {
      throw AuthError(
        kind: .sessionInvalidated, message: "Refresh Token Not Found",
        code: .refreshTokenNotFound)
    }

    var caught = false
    do {
      try refresh()
    } catch AuthError.Kind.sessionMissing {
      Issue.record("Matched the wrong kind")
    } catch AuthError.Kind.sessionInvalidated {
      caught = true
    } catch {
      Issue.record("Expected AuthError.Kind.sessionInvalidated, got \(error)")
    }
    #expect(caught)
  }

  @Test
  func patternsDoNotMatchOtherErrors() {
    let error: any Error = URLError(.timedOut)

    #expect(!(AuthError.Code.unexpectedFailure ~= error))
    #expect(!(AuthError.Kind.transport ~= error))
  }

  @Test
  func codePatternDoesNotMatchAnErrorWithoutACode() {
    let error: any Error = AuthError.sessionMissing

    #expect(!(AuthError.Code.sessionNotFound ~= error))
  }

  @Test
  func apiErrorCarriesResponse() {
    var headers = HTTPFields()
    headers[.sbRequestID] = "req-1"
    let error = AuthError(
      kind: .server,
      message: "API Error",
      code: .emailConflictIdentityNotDeletable,
      response: HTTPErrorResponse(status: 422, headers: headers, body: Data())
    )

    #expect(error.code == .emailConflictIdentityNotDeletable)
    #expect(error.response?.status == 422)
    #expect(error.response?.requestID == "req-1")
    #expect(error.description == "AuthError(server): API Error [status 422, request req-1]")
  }

  @Test
  func kindIsOpen() {
    let future = AuthError.Kind(rawValue: "somethingNew")

    #expect(future.rawValue == "somethingNew")
    #expect(future != .server)
  }

  @Test
  func conformsToSupabaseError() {
    let error: any Error = AuthError.sessionMissing

    #expect((error as? any SupabaseError)?.message == "Auth session missing.")
  }

  @Test
  func webAuthnCodeRawValues() {
    #expect(AuthError.Code.webAuthnChallengeNotFound.rawValue == "webauthn_challenge_not_found")
    #expect(AuthError.Code.webAuthnChallengeExpired.rawValue == "webauthn_challenge_expired")
    #expect(AuthError.Code.webAuthnVerificationFailed.rawValue == "webauthn_verification_failed")
    #expect(AuthError.Code.webAuthnCredentialExists.rawValue == "webauthn_credential_exists")
    #expect(AuthError.Code.tooManyPasskeys.rawValue == "too_many_passkeys")
  }

  @Test
  func codeEquality() {
    #expect(AuthError.Code.badJWT == AuthError.Code(rawValue: "bad_jwt"))
    #expect(AuthError.Code.sessionExpired == "session_expired")
    #expect(AuthError.Code.badJWT != AuthError.Code.sessionExpired)
  }

  @Test
  func codeAcceptsAStringLiteral() {
    let code: AuthError.Code = "custom_error"

    #expect(code.rawValue == "custom_error")
    #expect(AuthError.Code.badJWT.rawValue == "bad_jwt")
  }

  @Test
  func codeHashable() {
    let set: Set<AuthError.Code> = [.badJWT, .sessionExpired, .userNotFound]
    #expect(set.contains(.badJWT))
    #expect(set.contains(.sessionExpired))
    #expect(!set.contains(.emailExists))
  }
}
