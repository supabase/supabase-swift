//
//  AuthPasskeys.swift
//  Auth
//
//  Created by Guilherme Souza on 30/10/26.
//

public import Foundation

#if canImport(AuthenticationServices) && !os(watchOS)
  public import AuthenticationServices
#endif

extension AuthClient {
  /// Namespace for signing in with passkeys and managing the current user's passkeys.
  ///
  /// - Warning: Experimental. The passkey endpoints are not in the Auth OpenAPI spec yet. Opt in
  ///   with `@_spi(Experimental) import Supabase`.
  @_spi(Experimental)
  public var passkeys: AuthPasskeys {
    AuthPasskeys(client: self)
  }
}

/// Passkeys as a first factor: sign-in, registration, and management of the current user's
/// passkeys.
///
/// Access this namespace via ``AuthClient/passkeys``. WebAuthn as a second factor lives on
/// ``AuthMFA``.
///
/// ## Topics
///
/// ### Running a ceremony
/// - ``signIn(anchor:)``
/// - ``register(anchor:)``
///
/// ### Managing passkeys
/// - ``list()``
/// - ``rename(id:friendlyName:)``
/// - ``delete(id:)``
///
/// ### Driving the authenticator yourself
/// - ``authenticationOptions()``
/// - ``verifyAuthentication(challengeID:credential:)``
/// - ``registrationOptions()``
/// - ``verifyRegistration(challengeID:credential:)``
@_spi(Experimental)
public struct AuthPasskeys: Sendable {
  /// Held strongly, as ``AuthMFA`` holds it.
  let client: AuthClient

  private var dependencies: Dependencies { client.dependencies }

  /// Fetches credential creation options to register a new passkey for the current user.
  ///
  /// Requires a session. Forward ``PasskeyRegistrationOptions/options`` to the authenticator,
  /// then submit its result with ``verifyRegistration(challengeID:credential:)``.
  public func registrationOptions() async throws -> PasskeyRegistrationOptions {
    try await dependencies.sessionAPI.authorizedExecute {
      dependencies.authAPI.passkeyRegistrationOptions(accessToken: $0)
    }
  }

  /// Stores a newly created passkey for the current user.
  ///
  /// The server names the passkey after the authenticator that made it. Change the name with
  /// ``rename(id:friendlyName:)``.
  ///
  /// - Parameters:
  ///   - challengeID: ``PasskeyRegistrationOptions/challengeID``.
  ///   - credential: The W3C `PublicKeyCredential` JSON the authenticator produced.
  /// - Returns: The stored passkey.
  @discardableResult
  public func verifyRegistration(
    challengeID: UUID,
    credential: JSONValue
  ) async throws -> PasskeyListItem {
    try await dependencies.sessionAPI.authorizedExecute {
      try dependencies.authAPI.verifyPasskeyRegistration(
        challengeID: challengeID, credential: credential, accessToken: $0)
    }
  }

  /// Fetches assertion options to sign in with a passkey.
  ///
  /// Needs no session. Forward ``PasskeyAuthenticationOptions/options`` to the authenticator,
  /// then submit its result with ``verifyAuthentication(challengeID:credential:)``.
  public func authenticationOptions() async throws -> PasskeyAuthenticationOptions {
    try await dependencies.sessionAPI.execute(dependencies.authAPI.passkeyAuthenticationOptions())
  }

  /// Verifies a passkey assertion, stores the new session, and emits `signedIn`.
  ///
  /// - Parameters:
  ///   - challengeID: ``PasskeyAuthenticationOptions/challengeID``.
  ///   - credential: The W3C `PublicKeyCredential` JSON the authenticator produced.
  /// - Returns: The new session, at `aal1`.
  @discardableResult
  public func verifyAuthentication(
    challengeID: UUID,
    credential: JSONValue
  ) async throws -> Session {
    let session = try await dependencies.sessionAPI.execute(
      dependencies.authAPI.verifyPasskeyAuthentication(
        challengeID: challengeID, credential: credential)
    )
    try await dependencies.sessionStore.commit(.signedIn(session, event: .signedIn))
    return session
  }

  /// Lists the passkeys registered for the current user.
  public func list() async throws -> [PasskeyListItem] {
    try await dependencies.sessionAPI.authorizedExecute {
      dependencies.authAPI.listPasskeys(accessToken: $0)
    }
  }

  /// Renames a passkey of the current user.
  ///
  /// - Parameters:
  ///   - id: ``PasskeyListItem/id``.
  ///   - friendlyName: The new name, at most 120 characters.
  /// - Returns: The updated passkey.
  @discardableResult
  public func rename(id: UUID, friendlyName: String) async throws -> PasskeyListItem {
    try await dependencies.sessionAPI.authorizedExecute {
      try dependencies.authAPI.renamePasskey(id: id, friendlyName: friendlyName, accessToken: $0)
    }
  }

  /// Deletes a passkey of the current user.
  ///
  /// - Parameter id: ``PasskeyListItem/id``.
  public func delete(id: UUID) async throws {
    try await dependencies.sessionAPI.authorizedExecute {
      dependencies.authAPI.deletePasskey(id: id, accessToken: $0)
    }
  }
}

#if canImport(AuthenticationServices) && !os(watchOS)
  extension AuthPasskeys {
    /// Signs in with a passkey: fetches assertion options, shows the system passkey sheet, and
    /// verifies the assertion.
    ///
    /// The relying party is the `rpId` the server returns, so the app's Associated Domains
    /// entitlement must list `webcredentials:<rpId>`.
    ///
    /// - Parameter anchor: The window to show the sheet from. `nil` uses the app's key window. An
    ///   app extension has no key window to find, so pass one there.
    /// - Returns: The new session, at `aal1`.
    /// - Throws: `CancellationError` when the user dismisses the sheet. An error of kind
    ///   ``AuthError/Kind-swift.struct/passkeyCeremonyFailed`` when the authenticator fails.
    @discardableResult
    @MainActor
    public func signIn(anchor: ASPresentationAnchor? = nil) async throws -> Session {
      try await signIn(anchor: anchor, authenticator: .live)
    }

    @MainActor
    func signIn(
      anchor: ASPresentationAnchor?,
      authenticator: WebAuthnAuthenticator
    ) async throws -> Session {
      let options = try await authenticationOptions()
      let credential = try await authenticator.authenticate(
        WebAuthnRequestOptions(publicKey: options.options), anchor)
      return try await verifyAuthentication(
        challengeID: options.challengeID, credential: credential)
    }

    /// Registers a new passkey for the current user: fetches creation options, shows the system
    /// passkey sheet, and stores the new passkey.
    ///
    /// The relying party is the `rp.id` the server returns, so the app's Associated Domains
    /// entitlement must list `webcredentials:<rp.id>`. The server names the passkey after the
    /// authenticator; change it with ``rename(id:friendlyName:)``.
    ///
    /// - Parameter anchor: The window to show the sheet from. `nil` uses the app's key window. An
    ///   app extension has no key window to find, so pass one there.
    /// - Returns: The stored passkey.
    /// - Throws: `CancellationError` when the user dismisses the sheet. An error of kind
    ///   ``AuthError/Kind-swift.struct/passkeyCeremonyFailed`` when the authenticator fails. On
    ///   iOS 18, macOS 15, and visionOS 2 or later, its code is
    ///   ``ErrorCode/webAuthnCredentialExists`` when this device already holds one of the user's
    ///   passkeys.
    @discardableResult
    @MainActor
    public func register(anchor: ASPresentationAnchor? = nil) async throws -> PasskeyListItem {
      try await register(anchor: anchor, authenticator: .live)
    }

    @MainActor
    func register(
      anchor: ASPresentationAnchor?,
      authenticator: WebAuthnAuthenticator
    ) async throws -> PasskeyListItem {
      let options = try await registrationOptions()
      let credential = try await authenticator.register(
        WebAuthnCreationOptions(publicKey: options.options), anchor)
      return try await verifyRegistration(challengeID: options.challengeID, credential: credential)
    }
  }
#endif
