//
//  AuthAdmin+Passkey.swift
//  Auth
//
//  Created by Guilherme Souza on 21/07/26.
//

public import Foundation
import HTTPTypes

extension AuthAdmin {
  /// Lists the passkeys registered for a user.
  ///
  /// - Parameter forUser: The user's unique identifier.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the browser.
  @_spi(Experimental)
  public func listPasskeys(forUser userId: UUID) async throws -> [PasskeyListItem] {
    try await api.execute(
      HTTPRequest(
        method: .get,
        url: url.appendingPathComponent("admin/users/\(userId)/passkeys")
      )
    ).decoded(decoder: decoder)
  }

  /// Deletes a passkey belonging to a user.
  ///
  /// - Parameters:
  ///   - id: The passkey's unique identifier.
  ///   - userId: The user's unique identifier.
  /// - Warning: Never expose your `secret` key on the client.
  @_spi(Experimental)
  public func deletePasskey(id passkeyId: UUID, forUser userId: UUID) async throws {
    _ = try await api.execute(
      HTTPRequest(
        method: .delete,
        url: url.appendingPathComponent(
          "admin/users/\(userId)/passkeys/\(passkeyId)")
      )
    )
  }
}
