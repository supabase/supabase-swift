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
    /// unverified, and its name blocks a new enrollment with the same name. Find it with
    /// ``listFactors()``, then finish it with ``verifyWebAuthn(factorID:anchor:)`` or remove it
    /// with ``unenroll(params:)``.
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
      let factor = try await enroll(params: .webAuthn(friendlyName: friendlyName))
      return try await verifyWebAuthn(
        factorID: factor.id, anchor: anchor, authenticator: authenticator)
    }

    /// Verifies a WebAuthn factor: requests a challenge, shows the system passkey sheet, and
    /// verifies the result.
    ///
    /// The server picks the ceremony: an assertion for a verified factor, a new credential for
    /// one that is not verified yet.
    ///
    /// - Parameters:
    ///   - factorID: ``Factor/id`` of a `webauthn` factor.
    ///   - anchor: The window to show the sheet from. `nil` uses the app's key window. An app
    ///     extension has no key window to find, so pass one there.
    /// - Returns: The session, now at `aal2`.
    /// - Throws: `CancellationError` when the user dismisses the sheet. An error of kind
    ///   ``AuthError/Kind-swift.struct/passkeyCeremonyFailed`` when the authenticator fails.
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
      let publicKey = try webauthn.publicKeyOptions()
      let credential: JSONValue
      switch webauthn.type {
      case .create:
        credential = try await authenticator.register(
          WebAuthnCreationOptions(publicKey: publicKey), anchor)
      case .request:
        credential = try await authenticator.authenticate(
          WebAuthnRequestOptions(publicKey: publicKey), anchor)
      default:
        throw AuthError.decoding("Unknown WebAuthn challenge type '\(webauthn.type.rawValue)'.")
      }
      return try await verify(
        params: MFAVerifyParams(
          factorId: factorID, challengeId: challengeID, type: webauthn.type,
          credentialResponse: credential)
      )
    }

    private func webAuthnChallenge(
      factorID: UUID
    ) async throws -> (UUID, WebAuthnChallengeResponseData) {
      let challenge = try await challenge(params: MFAChallengeParams(factorId: factorID))
      guard let webauthn = challenge.webauthn else {
        throw AuthError.decoding("The MFA challenge response has no 'webauthn' field.")
      }
      return (challenge.id, webauthn)
    }
  }
#endif
