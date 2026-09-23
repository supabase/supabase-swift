//
//  AuthMFARecoveryCodes.swift
//
//
//  Created by Ranbir Singh on 23/09/26.
//

import Foundation
import HTTPTypes

/// Single-use backup codes that let a user reach `aal2` when they cannot use any of their other
/// MFA factors, for example after losing an authenticator app.
///
/// Access this namespace via ``AuthMFA/recoveryCodes``.
///
/// A user has one set of recovery codes, and the codes themselves are returned exactly once, when
/// the set is created. Recovery codes can never be a user's only factor, so generate them once
/// another factor is verified.
///
/// > Warning: Recovery codes are an experimental Supabase Auth feature and have to be enabled on
/// > the Auth server before these methods can be used.
///
/// ```swift
/// let generated = try await client.auth.mfa.recoveryCodes.generate(friendlyName: "Backup codes")
/// // Show generated.codes to the user once and ask them to store the codes safely.
///
/// try await client.auth.mfa.recoveryCodes.verify(code: "K4M9-X7QP-2AB8-HT3Z")
/// ```
///
/// ## Topics
///
/// ### Creating and replacing codes
/// - ``generate(friendlyName:)``
/// - ``regenerate()``
///
/// ### Using codes
/// - ``verify(code:)``
///
/// ### Inspecting and removing
/// - ``status()``
/// - ``unenroll()``
public struct AuthMFARecoveryCodes: Sendable {
  let clientID: AuthClientID

  var configuration: AuthClient.Configuration { Dependencies[clientID].configuration }
  var api: APIClient { Dependencies[clientID].api }
  var encoder: JSONEncoder { Dependencies[clientID].resolvedEncoder }
  var decoder: JSONDecoder { Dependencies[clientID].resolvedDecoder }
  var sessionManager: SessionManager { Dependencies[clientID].sessionManager }
  var eventEmitter: AuthStateChangeEventEmitter { Dependencies[clientID].eventEmitter }

  private var url: URL { configuration.url.appendingPathComponent("factors/recovery-codes") }

  /// Returns how many recovery codes the user's current set holds and how many of them are still
  /// unused. Never returns the codes themselves.
  ///
  /// Works at any authenticator assurance level. When
  /// ``AuthMFARecoveryCodesStatusResponse/remaining`` reaches zero, prompt the user to call
  /// ``regenerate()``.
  ///
  /// - Returns: The enrollment status of the user's recovery codes.
  /// - Throws: An error with code `mfa_factor_not_found` when the user has no recovery codes.
  public func status() async throws -> AuthMFARecoveryCodesStatusResponse {
    try await api.authorizedExecute(HTTPRequest(method: .get, url: url))
      .decoded(decoder: decoder)
  }

  /// Generates the user's set of recovery codes.
  ///
  /// The codes come back in ``AuthMFARecoveryCodesGenerateResponse/codes`` and cannot be retrieved
  /// again, so show them to the user and ask them to store the codes safely.
  ///
  /// The session has to be at `aal2` and the user has to already have another verified factor. A
  /// user can only hold one set of recovery codes; use ``regenerate()`` to replace an existing set.
  ///
  /// - Parameter friendlyName: The name the factor is listed under in ``AuthMFA/listFactors()``,
  ///   unique among the user's factors. The server names it `Recovery codes` when omitted.
  /// - Returns: The new set of recovery codes.
  public func generate(
    friendlyName: String? = nil
  ) async throws -> AuthMFARecoveryCodesGenerateResponse {
    let body = try friendlyName.map { try encoder.encode(GenerateParams(friendlyName: $0)) }
    return try await api.authorizedExecute(HTTPRequest(method: .post, url: url), body: body)
      .decoded(decoder: decoder)
  }

  /// Verifies one of the user's recovery codes and upgrades the current session to `aal2`. Each
  /// code works only once.
  ///
  /// On success the stored session is replaced with the upgraded one, the user's other `aal1`
  /// sessions are signed out, and ``AuthChangeEvent/mfaChallengeVerified`` is emitted.
  ///
  /// - Parameter code: A recovery code, exactly as the user typed it. The server ignores letter
  ///   case, whitespace and `-` separators.
  /// - Returns: The upgraded session.
  /// - Throws: An error with code `mfa_verification_failed` when the code is wrong, already used or
  ///   missing.
  @discardableResult
  public func verify(code: String) async throws -> AuthMFAVerifyResponse {
    let response: AuthMFAVerifyResponse = try await api.authorizedExecute(
      HTTPRequest(method: .post, url: url.appendingPathComponent("verify")),
      body: encoder.encode(VerifyParams(code: code))
    )
    .decoded(decoder: decoder)

    await sessionManager.update(response)

    eventEmitter.emit(.mfaChallengeVerified, session: response, token: nil)

    return response
  }

  /// Replaces the user's recovery codes with a new set.
  ///
  /// Every remaining code from the previous set stops working immediately and any verification
  /// lockout is cleared. The factor keeps its id and friendly name. The session has to be at `aal2`.
  ///
  /// - Returns: The new set of recovery codes.
  /// - Throws: An error with code `mfa_factor_not_found` when the user has no recovery codes to
  ///   replace. Use ``generate(friendlyName:)`` instead.
  public func regenerate() async throws -> AuthMFARecoveryCodesGenerateResponse {
    try await api.authorizedExecute(
      HTTPRequest(method: .post, url: url.appendingPathComponent("regenerate"))
    )
    .decoded(decoder: decoder)
  }

  /// Removes the user's recovery codes factor and every code in it. The session has to be at
  /// `aal2`.
  ///
  /// - Returns: The id of the factor that was removed.
  /// - Throws: An error with code `mfa_factor_not_found` when the user has no recovery codes.
  @discardableResult
  public func unenroll() async throws -> AuthMFAUnenrollResponse {
    try await api.authorizedExecute(HTTPRequest(method: .delete, url: url))
      .decoded(decoder: decoder)
  }
}

private struct GenerateParams: Encodable {
  let friendlyName: String
}

private struct VerifyParams: Encodable {
  let code: String
}
