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
  @available(iOS 16.0, macOS 13.0, macCatalyst 16.0, visionOS 1.0, *)
  extension AuthMFA {
    // MARK: - WebAuthn MFA (high-level, native UI)

    /// Enrolls a new WebAuthn (passkey) factor, driving the full ceremony: enrolls the factor,
    /// requests a challenge, presents the native passkey registration UI via
    /// `AuthenticationServices`, and verifies the credential with the backend.
    ///
    /// - Parameters:
    ///   - friendlyName: Human readable name assigned to the factor.
    ///   - rpId: The relying party identifier (your app's associated domain, e.g. `example.com`).
    ///   - rpOrigins: Allowed relying party origins.
    ///   - presentationAnchor: The window to present the passkey UI from.
    @_spi(Experimental)
    @discardableResult
    @MainActor
    public func enrollWebAuthnFactor(
      friendlyName: String,
      rpId: String,
      rpOrigins: [String] = [],
      presentationAnchor: ASPresentationAnchor
    ) async throws -> AuthMFAVerifyResponse {
      try await _enrollWebAuthnFactor(
        friendlyName: friendlyName,
        rpId: rpId,
        rpOrigins: rpOrigins,
        presentationAnchor: presentationAnchor,
        authenticator: .live
      )
    }

    @MainActor
    func _enrollWebAuthnFactor(
      friendlyName: String,
      rpId: String,
      rpOrigins: [String],
      presentationAnchor: ASPresentationAnchor,
      authenticator: WebAuthnAuthenticator
    ) async throws -> AuthMFAVerifyResponse {
      let enrolled = try await enroll(params: .webAuthn(friendlyName: friendlyName))
      let challengeResponse = try await challenge(
        params: MFAChallengeParams(
          factorId: enrolled.id,
          webAuthn: WebAuthnChallengeOptions(
            rpId: rpId,
            rpOrigins: rpOrigins.isEmpty ? nil : rpOrigins
          )
        )
      )
      guard let webauthn = challengeResponse.webauthn else {
        throw WebAuthnError.missingField("webauthn")
      }
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
    /// - Parameters:
    ///   - factorId: The ID of the factor to verify.
    ///   - rpId: The relying party identifier (your app's associated domain, e.g. `example.com`).
    ///   - rpOrigins: Allowed relying party origins.
    ///   - presentationAnchor: The window to present the passkey UI from.
    @_spi(Experimental)
    @discardableResult
    @MainActor
    public func verifyWebAuthnFactor(
      factorId: String,
      rpId: String,
      rpOrigins: [String] = [],
      presentationAnchor: ASPresentationAnchor
    ) async throws -> AuthMFAVerifyResponse {
      try await _verifyWebAuthnFactor(
        factorId: factorId,
        rpId: rpId,
        rpOrigins: rpOrigins,
        presentationAnchor: presentationAnchor,
        authenticator: .live
      )
    }

    @MainActor
    func _verifyWebAuthnFactor(
      factorId: String,
      rpId: String,
      rpOrigins: [String],
      presentationAnchor: ASPresentationAnchor,
      authenticator: WebAuthnAuthenticator
    ) async throws -> AuthMFAVerifyResponse {
      let challengeResponse = try await challenge(
        params: MFAChallengeParams(
          factorId: factorId,
          webAuthn: WebAuthnChallengeOptions(
            rpId: rpId,
            rpOrigins: rpOrigins.isEmpty ? nil : rpOrigins
          )
        )
      )
      guard let webauthn = challengeResponse.webauthn else {
        throw WebAuthnError.missingField("webauthn")
      }
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
