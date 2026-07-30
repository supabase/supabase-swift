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
  /// - Parameter userId: The user's unique identifier.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the browser.
  @_spi(Experimental)
  public func listPasskeys(userId: UUID) async throws -> [PasskeyListItem] {
    try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("admin/users/\(userId)/passkeys"),
        method: .get
      )
    ).decoded(decoder: configuration.decoder)
  }

  /// Deletes a passkey belonging to a user.
  ///
  /// - Parameters:
  ///   - userId: The user's unique identifier.
  ///   - passkeyId: The passkey's unique identifier.
  /// - Warning: Never expose your `secret` key on the client.
  @_spi(Experimental)
  public func deletePasskey(userId: UUID, passkeyId: UUID) async throws {
    _ = try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent(
          "admin/users/\(userId)/passkeys/\(passkeyId)"),
        method: .delete
      )
    )
  }
}
