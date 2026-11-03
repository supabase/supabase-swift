//
//  AuthMFA+WebAuthn.swift
//  Auth
//
//  Created by Guilherme Souza on 11/06/26.
//

public import Foundation

#if canImport(AuthenticationServices) && !os(watchOS)
  public import AuthenticationServices

  extension AuthMFA {
    /// Enrolls a WebAuthn second factor: enrolls the factor, requests a challenge, shows the
    /// system passkey sheet, and verifies the new credential.
    ///
    /// The relying party is the `rp.id` the server returns, so the app's Associated Domains
    /// entitlement must list `webcredentials:<rp.id>`.
    ///
    /// When the ceremony or the verification fails, the server keeps the new factor as
    /// unverified, and its name blocks a new enrollment with the same name. Find it in
    /// ``MFAFactors/unverified`` of ``factors()`` and remove it with ``unenroll(factorID:)``.
    ///
    /// - Parameters:
    ///   - friendlyName: A name for the factor.
    ///   - anchor: The window to show the sheet from. `nil` uses the app's key window. An app
    ///     extension has no key window to find, so pass one there.
    /// - Returns: The session, now at `aal2`.
    /// - Throws: `CancellationError` when the user dismisses the sheet. An error of kind
    ///   ``AuthError/Kind-swift.struct/passkeyCeremonyFailed`` when the authenticator fails.
    @_spi(Experimental)
    @discardableResult
    @MainActor
    public func enrollWebAuthn(
      friendlyName: String? = nil,
      anchor: ASPresentationAnchor? = nil
    ) async throws -> Session {
      try await enrollWebAuthn(friendlyName: friendlyName, anchor: anchor, authenticator: .live)
    }

    @MainActor
    func enrollWebAuthn(
      friendlyName: String?,
      anchor: ASPresentationAnchor?,
      authenticator: WebAuthnAuthenticator
    ) async throws -> Session {
      let factorID = try await enrollWebAuthnFactor(friendlyName: friendlyName)
      let (challengeID, webauthn) = try await webAuthnChallenge(factorID: factorID)
      guard webauthn.type == .create else {
        throw unexpectedChallengeType(webauthn.type)
      }
      let credential = try await authenticator.register(
        WebAuthnCreationOptions(publicKey: try webauthn.publicKeyOptions()), anchor)
      return try await verify(
        factorID: factorID, challengeID: challengeID, type: .create, credentialResponse: credential
      )
    }

    /// Steps the session up to `aal2` with a verified WebAuthn factor: requests a challenge, shows
    /// the system passkey sheet, and verifies the assertion.
    ///
    /// This method never registers a credential. For a factor that is not verified, the server
    /// asks for a new credential instead of an assertion, so this method throws before it shows
    /// the sheet. Register a factor with ``enrollWebAuthn(friendlyName:anchor:)``.
    ///
    /// - Parameters:
    ///   - factorID: ``Factor/id`` of a verified `webauthn` factor.
    ///   - anchor: The window to show the sheet from. `nil` uses the app's key window. An app
    ///     extension has no key window to find, so pass one there.
    /// - Returns: The session, now at `aal2`.
    /// - Throws: An error of kind ``AuthError/Kind-swift.struct/mfaFactorNotVerified`` when the
    ///   factor is not verified. `CancellationError` when the user dismisses the sheet. An error
    ///   of kind ``AuthError/Kind-swift.struct/passkeyCeremonyFailed`` when the authenticator
    ///   fails.
    @_spi(Experimental)
    @discardableResult
    @MainActor
    public func verifyWebAuthn(
      factorID: UUID,
      anchor: ASPresentationAnchor? = nil
    ) async throws -> Session {
      try await verifyWebAuthn(factorID: factorID, anchor: anchor, authenticator: .live)
    }

    @MainActor
    func verifyWebAuthn(
      factorID: UUID,
      anchor: ASPresentationAnchor?,
      authenticator: WebAuthnAuthenticator
    ) async throws -> Session {
      let (challengeID, webauthn) = try await webAuthnChallenge(factorID: factorID)
      switch webauthn.type {
      case .request:
        break
      case .create:
        // A `create` challenge registers a new credential, which only enrollment may do.
        throw AuthError(
          kind: .mfaFactorNotVerified,
          message: "The WebAuthn factor is not verified. Enroll a factor with enrollWebAuthn.")
      default:
        throw unexpectedChallengeType(webauthn.type)
      }
      let credential = try await authenticator.authenticate(
        WebAuthnRequestOptions(publicKey: try webauthn.publicKeyOptions()), anchor)
      return try await verify(
        factorID: factorID, challengeID: challengeID, type: .request, credentialResponse: credential
      )
    }

    private func webAuthnChallenge(
      factorID: UUID
    ) async throws -> (UUID, WebAuthnChallengeResponseData) {
      let challenge = try await challenge(factorID: factorID)
      guard let webauthn = challenge.webauthn else {
        throw AuthError.decoding("The MFA challenge response has no 'webauthn' field.")
      }
      return (challenge.id, webauthn)
    }

    private func unexpectedChallengeType(_ type: WebAuthnChallengeType) -> AuthError {
      AuthError.decoding("Unexpected WebAuthn challenge type '\(type.rawValue)'.")
    }
  }
#endif
