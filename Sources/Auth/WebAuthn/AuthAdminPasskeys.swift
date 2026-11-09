//
//  AuthAdminPasskeys.swift
//  Auth
//
//  Created by Guilherme Souza on 30/10/26.
//

public import Foundation

extension AuthAdminClient {
  /// Contains the passkey administration methods.
  ///
  /// - Warning: Experimental. Requires the `secret` key; never expose it in a client app.
  @_spi(Experimental)
  public var passkeys: AuthAdminPasskeys {
    AuthAdminPasskeys(admin: self)
  }
}

/// Admin operations on a user's passkeys.
///
/// Access this namespace via ``AuthAdminClient/passkeys``.
///
/// > Warning: These methods require the secret key. Never expose this key
/// > in a browser or mobile app. Call these methods from a secure server-side environment only.
@_spi(Experimental)
public struct AuthAdminPasskeys: Sendable {
  let admin: AuthAdminClient

  /// Lists the passkeys registered for a user.
  ///
  /// - Parameter userID: The user's unique identifier.
  public func list(forUser userID: UUID) async throws -> [PasskeyListItem] {
    try await admin.api.execute(admin.authAPI.adminListPasskeys(userID: userID))
  }

  /// Deletes a passkey of a user.
  ///
  /// - Parameters:
  ///   - id: ``PasskeyListItem/id``.
  ///   - userID: The user's unique identifier.
  public func delete(id: UUID, forUser userID: UUID) async throws {
    try await admin.api.execute(admin.authAPI.adminDeletePasskey(id: id, userID: userID))
  }
}
