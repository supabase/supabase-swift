//
//  AuthAdmin.swift
//
//
//  Created by Guilherme Souza on 25/01/24.
//

import Foundation
@_spi(Internal) import _Helpers

public actor AuthAdmin {
  @Dependency(\.configuration)
  private var configuration: AuthClient.Configuration

  @Dependency(\.api)
  private var api: APIClient

  /// Delete a user. Requires `service_role` key.
  /// - Parameter id: The id of the user you want to delete.
  /// - Parameter shouldSoftDelete: If true, then the user will be soft-deleted (setting
  /// `deleted_at` to the current timestamp and disabling their account while preserving their data)
  /// from the auth schema.
  ///
  /// - Warning: Never expose your `service_role` key on the client.
  public func deleteUser(id: String, shouldSoftDelete: Bool = false) async throws {
    _ = try await api.execute(
      Request(
        path: "/admin/users/\(id)",
        method: .delete,
        body: configuration.encoder.encode(DeleteUserRequest(shouldSoftDelete: shouldSoftDelete))
      )
    )
  }
}
