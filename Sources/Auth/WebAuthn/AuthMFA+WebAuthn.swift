//
//  AuthMFA+WebAuthn.swift
//  Auth
//
//  Created by Guilherme Souza on 11/06/26.
//

import Foundation

#if canImport(AuthenticationServices)
  import AuthenticationServices
#endif

#if canImport(AuthenticationServices) && !os(tvOS) && !os(watchOS)
  extension AuthMFA {
    // MARK: - WebAuthn MFA (high-level, native UI)

    /// Enrolls a new WebAuthn (passkey) factor, driving the full ceremony: enrolls the factor,
    /// requests a challenge, presents the native passkey registration UI via
    /// `AuthenticationServices`, and verifies the credential with the backend.
    ///
    /// The relying-party identifier is read from the `rp.id` field of the W3C creation options
    /// returned by the server — no client-side configuration needed.
    ///
    /// - Parameters:
    ///   - friendlyName: Human readable name assigned to the factor.
    ///   - presentationAnchor: The window to present the passkey UI from.
    @_spi(Experimental)
    @discardableResult
    @MainActor
    public func enrollWebAuthnFactor(
      friendlyName: String,
      presentationAnchor: ASPresentationAnchor
    ) async throws -> AuthMFAVerifyResponse {
      try await _enrollWebAuthnFactor(
        friendlyName: friendlyName,
        presentationAnchor: presentationAnchor,
        authenticator: .live
      )
    }

    @MainActor
    func _enrollWebAuthnFactor(
      friendlyName: String,
      presentationAnchor: ASPresentationAnchor,
      authenticator: WebAuthnAuthenticator
    ) async throws -> AuthMFAVerifyResponse {
      let enrolled = try await enroll(params: .webAuthn(friendlyName: friendlyName))
      let challengeResponse = try await challenge(
        params: MFAChallengeParams(factorId: enrolled.id)
      )
      guard let webauthn = challengeResponse.webauthn else {
        throw WebAuthnError.missingField("webauthn")
      }
      let rpId = try webauthn.credentialOptions.webAuthnCreationRpId()
      let credentialResponse = try await authenticator.register(
        webauthn.credentialOptions, rpId, presentationAnchor
      )
      return try await verify(
        params: MFAVerifyParams(
          factorId: enrolled.id,
          challengeId: challengeResponse.id,
          credentialResponse: credentialResponse
        )
      )
    }

    /// Authenticates an existing WebAuthn (passkey) factor, driving the full ceremony: requests a
    /// challenge, presents the native passkey assertion UI via `AuthenticationServices`, and
    /// verifies the credential with the backend.
    ///
    /// The relying-party identifier is read from the `rpId` field of the W3C assertion options
    /// returned by the server — no client-side configuration needed.
    ///
    /// - Parameters:
    ///   - factorId: The ID of the factor to verify.
    ///   - presentationAnchor: The window to present the passkey UI from.
    @_spi(Experimental)
    @discardableResult
    @MainActor
    public func verifyWebAuthnFactor(
      factorId: String,
      presentationAnchor: ASPresentationAnchor
    ) async throws -> AuthMFAVerifyResponse {
      try await _verifyWebAuthnFactor(
        factorId: factorId,
        presentationAnchor: presentationAnchor,
        authenticator: .live
      )
    }

    @MainActor
    func _verifyWebAuthnFactor(
      factorId: String,
      presentationAnchor: ASPresentationAnchor,
      authenticator: WebAuthnAuthenticator
    ) async throws -> AuthMFAVerifyResponse {
      let challengeResponse = try await challenge(
        params: MFAChallengeParams(factorId: factorId)
      )
      guard let webauthn = challengeResponse.webauthn else {
        throw WebAuthnError.missingField("webauthn")
      }
      let rpId = try webauthn.credentialOptions.webAuthnAssertionRpId()
      let credentialResponse = try await authenticator.authenticate(
        webauthn.credentialOptions, rpId, presentationAnchor
      )
      return try await verify(
        params: MFAVerifyParams(
          factorId: factorId,
          challengeId: challengeResponse.id,
          credentialResponse: credentialResponse
        )
      )
    }
  }
#endif
