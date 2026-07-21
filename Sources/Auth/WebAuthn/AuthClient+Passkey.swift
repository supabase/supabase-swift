//
//  AuthClient+Passkey.swift
//  Auth
//
//  Created by Guilherme Souza on 11/06/26.
//

public import Foundation
import HTTPTypes

#if canImport(AuthenticationServices)
  public import AuthenticationServices
#endif

extension AuthClient {
  // MARK: - First-factor passkeys (lower-level)
  //
  // WebAuthn/passkey support is experimental — these methods are exposed under the `Experimental`
  // SPI. Opt in with `@_spi(Experimental) import Supabase`.
  //
  // These methods only perform the network exchange. The caller is responsible for driving the
  // platform authenticator (e.g. via `ASAuthorizationController`) between fetching options and
  // submitting the credential response. For an end-to-end flow on iOS 16+/macOS 13+, prefer the
  // `signInWithPasskey(presentationAnchor:)` and `registerPasskey(presentationAnchor:)` helpers.

  /// Fetches credential creation options to register a new passkey for the current user.
  ///
  /// Requires an authenticated session. ``PasskeyRegistrationOptions/options`` are W3C
  /// `PublicKeyCredentialCreationOptions` to forward to the platform authenticator. After running
  /// the authenticator, submit the result with
  /// ``verifyPasskeyRegistration(challengeId:credentialResponse:)``.
  @_spi(Experimental)
  public func getPasskeyRegistrationOptions() async throws -> PasskeyRegistrationOptions {
    try await Dependencies[clientID].api.authorizedExecute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("passkeys/registration/options"),
        method: .post
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  /// Stores a newly created passkey for the current user.
  ///
  /// - Parameters:
  ///   - challengeId: The challenge ID returned by ``getPasskeyRegistrationOptions()``.
  ///   - credentialResponse: The W3C credential produced by the authenticator.
  /// - Returns: The stored passkey.
  @_spi(Experimental)
  @discardableResult
  public func verifyPasskeyRegistration(
    challengeId: String,
    credentialResponse: AnyJSON
  ) async throws -> PasskeyListItem {
    try await Dependencies[clientID].api.authorizedExecute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("passkeys/registration/verify"),
        method: .post,
        body: encodeWebAuthnBody([
          "challenge_id": .string(challengeId),
          "credential": credentialResponse,
        ])
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  /// Fetches assertion options to authenticate with a passkey.
  ///
  /// Does not require an authenticated session. ``PasskeyAuthenticationOptions/options`` are W3C
  /// `PublicKeyCredentialRequestOptions` to forward to the platform authenticator. After running
  /// the authenticator, submit the result with
  /// ``verifyPasskeyAuthentication(challengeId:credentialResponse:)``.
  @_spi(Experimental)
  public func getPasskeyAuthenticationOptions() async throws -> PasskeyAuthenticationOptions {
    try await Dependencies[clientID].api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("passkeys/authentication/options"),
        method: .post
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  /// Verifies a passkey assertion and establishes a session.
  ///
  /// - Parameters:
  ///   - challengeId: The challenge ID returned by ``getPasskeyAuthenticationOptions()``.
  ///   - credentialResponse: The W3C assertion produced by the authenticator.
  /// - Returns: The authentication response containing the new session.
  @_spi(Experimental)
  @discardableResult
  public func verifyPasskeyAuthentication(
    challengeId: String,
    credentialResponse: AnyJSON
  ) async throws -> AuthResponse {
    let response: AuthResponse = try await Dependencies[clientID].api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("passkeys/authentication/verify"),
        method: .post,
        body: encodeWebAuthnBody([
          "challenge_id": .string(challengeId),
          "credential": credentialResponse,
        ])
      )
    )
    .decoded(decoder: configuration.decoder)

    if let session = response.session {
      await Dependencies[clientID].sessionManager.update(session)
      Dependencies[clientID].eventEmitter.emit(.signedIn, session: session)
    }

    return response
  }

  /// Lists the passkeys registered for the current user.
  @_spi(Experimental)
  public func listPasskeys() async throws -> [PasskeyListItem] {
    try await Dependencies[clientID].api.authorizedExecute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("passkeys/"),
        method: .get
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  /// Renames a passkey.
  ///
  /// - Parameters:
  ///   - id: The ID of the passkey to rename.
  ///   - friendlyName: The new human readable name.
  /// - Returns: The updated passkey.
  @_spi(Experimental)
  @discardableResult
  public func renamePasskey(id: UUID, friendlyName: String) async throws -> PasskeyListItem {
    try await Dependencies[clientID].api.authorizedExecute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("passkeys/\(id)"),
        method: .patch,
        // Dictionary keys are not transformed by the snake_case strategy, so spell it out.
        body: configuration.encoder.encode(["friendly_name": friendlyName])
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  /// Removes a passkey.
  ///
  /// - Parameter id: The ID of the passkey to remove.
  @_spi(Experimental)
  public func deletePasskey(id: UUID) async throws {
    try await Dependencies[clientID].api.authorizedExecute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("passkeys/\(id)"),
        method: .delete
      )
    )
  }
}

#if canImport(AuthenticationServices) && !os(tvOS) && !os(watchOS)
  extension AuthClient {
    // MARK: - First-factor passkeys (high-level, native UI)

    /// Signs in with a passkey, driving the full ceremony: fetches assertion options, presents the
    /// native passkey UI via `AuthenticationServices`, submits the assertion, and returns the new
    /// session.
    ///
    /// The relying-party identifier is read from the `rpId` field of the W3C assertion options
    /// returned by the server — no client-side configuration needed.
    ///
    /// - Parameter presentationAnchor: The window to present the passkey UI from.
    @_spi(Experimental)
    @discardableResult
    @MainActor
    public func signInWithPasskey(
      presentationAnchor: ASPresentationAnchor
    ) async throws -> AuthResponse {
      try await _signInWithPasskey(
        presentationAnchor: presentationAnchor,
        authenticator: .live
      )
    }

    @MainActor
    func _signInWithPasskey(
      presentationAnchor: ASPresentationAnchor,
      authenticator: WebAuthnAuthenticator
    ) async throws -> AuthResponse {
      let options = try await getPasskeyAuthenticationOptions()
      let rpId = try options.options.webAuthnAssertionRpId()
      let credentialResponse = try await authenticator.authenticate(
        options.options, rpId, presentationAnchor
      )
      return try await verifyPasskeyAuthentication(
        challengeId: options.challengeId,
        credentialResponse: credentialResponse
      )
    }

    /// Registers a new passkey for the current user, driving the full ceremony: fetches creation
    /// options, presents the native passkey UI, and stores the resulting passkey.
    ///
    /// The relying-party identifier is read from the `rp.id` field of the W3C creation options
    /// returned by the server — no client-side configuration needed.
    ///
    /// - Parameter presentationAnchor: The window to present the passkey UI from.
    @_spi(Experimental)
    @discardableResult
    @MainActor
    public func registerPasskey(
      presentationAnchor: ASPresentationAnchor
    ) async throws -> PasskeyListItem {
      try await _registerPasskey(
        presentationAnchor: presentationAnchor,
        authenticator: .live
      )
    }

    @MainActor
    func _registerPasskey(
      presentationAnchor: ASPresentationAnchor,
      authenticator: WebAuthnAuthenticator
    ) async throws -> PasskeyListItem {
      let options = try await getPasskeyRegistrationOptions()
      let rpId = try options.options.webAuthnCreationRpId()
      let credentialResponse = try await authenticator.register(
        options.options, rpId, presentationAnchor
      )
      return try await verifyPasskeyRegistration(
        challengeId: options.challengeId,
        credentialResponse: credentialResponse
      )
    }
  }
#endif
